package api

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

// GET /jobs/{id}
func (h *handler) getJob(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("id")
	j, err := h.queue.Get(r.Context(), jobID)
	if err != nil {
		jsonError(w, "job not found", http.StatusNotFound)
		return
	}
	jsonOK(w, map[string]any{
		"jobId":      j.ID,
		"albumId":    j.AlbumID,
		"status":     j.Status,
		"error":      j.Error,
		"startedAt":  nullTime(j.StartedAt),
		"finishedAt": nullTime(j.FinishedAt),
	}, http.StatusOK)
}

// POST /albums/{id}/scrape-tracks — resolves and persists MP3 URLs for all tracks
// that don't yet have one. Sequential to avoid Cloudflare rate-limiting.
func (h *handler) scrapeAlbumTracks(w http.ResponseWriter, r *http.Request) {
	albumID := r.PathValue("id")
	album, err := h.store.Album(r.Context(), albumID)
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "album not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	var resolved, failed, skipped int
	for _, t := range album.Tracks {
		if t.MP3URL != "" {
			skipped++
			continue
		}
		if t.PageURL == "" {
			failed++
			continue
		}
		mp3URL, resolveErr := h.fetcher.SongMP3(r.Context(), t.PageURL)
		if resolveErr != nil {
			failed++
			continue
		}
		_ = h.store.SetTrackMP3URL(r.Context(), t.ID, mp3URL)
		resolved++
	}
	jsonOK(w, map[string]int{"resolved": resolved, "failed": failed, "skipped": skipped}, http.StatusOK)
}

// GET /tracks/{id}/stream — serves the locally-downloaded MP3 file if available,
// otherwise resolves the direct MP3 URL and redirects to it.
func (h *handler) streamTrack(w http.ResponseWriter, r *http.Request) {
	trackID := r.PathValue("id")
	tr, err := h.store.Track(r.Context(), trackID)
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "track not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	// Serve local file if already downloaded.
	if tr.LocalPath != "" {
		if _, statErr := os.Stat(tr.LocalPath); statErr == nil {
			w.Header().Set("Content-Type", "audio/mpeg")
			http.ServeFile(w, r, tr.LocalPath)
			return
		}
	}
	// Resolve MP3URL on demand if not yet cached.
	if tr.MP3URL == "" {
		if tr.PageURL == "" {
			jsonError(w, "track has no source URL", http.StatusServiceUnavailable)
			return
		}
		mp3URL, resolveErr := h.fetcher.SongMP3(r.Context(), tr.PageURL)
		if resolveErr != nil {
			jsonError(w, "failed to resolve mp3: "+resolveErr.Error(), http.StatusBadGateway)
			return
		}
		_ = h.store.SetTrackMP3URL(r.Context(), trackID, mp3URL)
		tr.MP3URL = mp3URL
	}
	http.Redirect(w, r, tr.MP3URL, http.StatusFound)
}

// GET /tracks/{id}/resolve — returns the direct MP3 URL without redirecting.
// ?force=1 re-scrapes even if a cached URL exists (use when cached URL is stale).
func (h *handler) resolveTrackURL(w http.ResponseWriter, r *http.Request) {
	trackID := r.PathValue("id")
	force := r.URL.Query().Get("force") == "1"
	tr, err := h.store.Track(r.Context(), trackID)
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "track not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	if force || tr.MP3URL == "" {
		if tr.PageURL == "" {
			jsonError(w, "track has no source URL", http.StatusServiceUnavailable)
			return
		}
		mp3URL, resolveErr := h.fetcher.SongMP3(r.Context(), tr.PageURL)
		if resolveErr != nil {
			jsonError(w, "failed to resolve mp3: "+resolveErr.Error(), http.StatusBadGateway)
			return
		}
		_ = h.store.SetTrackMP3URL(r.Context(), trackID, mp3URL)
		tr.MP3URL = mp3URL
	}
	jsonOK(w, map[string]string{"url": tr.MP3URL}, http.StatusOK)
}

// POST /tracks/{id}/fetch — resolves the MP3 URL and downloads the file locally.
// Synchronous: returns when the file is on disk.
func (h *handler) fetchTrackLocal(w http.ResponseWriter, r *http.Request) {
	trackID := r.PathValue("id")
	tr, err := h.store.Track(r.Context(), trackID)
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "track not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}

	// Already downloaded.
	if tr.LocalPath != "" {
		if _, err := os.Stat(tr.LocalPath); err == nil {
			jsonOK(w, map[string]string{"status": "done", "localPath": tr.LocalPath}, http.StatusOK)
			return
		}
	}

	// Resolve mp3URL if needed.
	if tr.MP3URL == "" {
		if tr.PageURL == "" {
			jsonError(w, "track has no page URL", http.StatusServiceUnavailable)
			return
		}
		mp3URL, err := h.fetcher.SongMP3(r.Context(), tr.PageURL)
		if err != nil {
			jsonError(w, "failed to resolve mp3: "+err.Error(), http.StatusBadGateway)
			return
		}
		_ = h.store.SetTrackMP3URL(r.Context(), trackID, mp3URL)
		tr.MP3URL = mp3URL
	}

	// Determine destination path.
	albumID, err := h.store.TrackAlbumID(r.Context(), trackID)
	if err != nil {
		jsonError(w, "album not found for track", http.StatusInternalServerError)
		return
	}
	destPath := filepath.Join(h.dataDir, albumID, "tracks", fmt.Sprintf("%s.mp3", trackID))

	if err := h.fetcher.Download(r.Context(), tr.MP3URL, destPath); err != nil {
		jsonError(w, "download failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	if err := h.store.SetTrackLocalPath(r.Context(), trackID, destPath); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}

	jsonOK(w, map[string]string{"status": "done", "localPath": destPath}, http.StatusOK)
}

// GET /tracks/{id}/download — serves local file with Content-Disposition for browser save.
func (h *handler) downloadTrack(w http.ResponseWriter, r *http.Request) {
	trackID := r.PathValue("id")
	tr, err := h.store.Track(r.Context(), trackID)
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "track not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	if tr.LocalPath == "" {
		jsonError(w, "track not downloaded", http.StatusConflict)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="`+tr.Name+`.mp3"`)
	w.Header().Set("Content-Type", "audio/mpeg")
	http.ServeFile(w, r, tr.LocalPath)
}

// POST /scrape/pending — resolves mp3_url for all tracks that have page_url but no mp3_url.
func (h *handler) scrapeAllPending(w http.ResponseWriter, r *http.Request) {
	tracks, err := h.store.PendingTracks(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	resolved, failed := 0, 0
	for _, t := range tracks {
		mp3URL, err := h.fetcher.SongMP3(r.Context(), t.PageURL)
		if err != nil {
			failed++
			continue
		}
		if err := h.store.SetTrackMP3URL(r.Context(), t.ID, mp3URL); err != nil {
			failed++
			continue
		}
		resolved++
	}
	jsonOK(w, map[string]int{"resolved": resolved, "failed": failed, "total": len(tracks)}, http.StatusOK)
}
