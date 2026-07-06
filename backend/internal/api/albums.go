package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

// POST /albums
func (h *handler) postAlbum(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.URL) == "" {
		jsonError(w, "url is required", http.StatusBadRequest)
		return
	}
	if err := validateURL(req.URL); err != nil {
		jsonError(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}

	// Already cached?
	albumID := store.AlbumID(req.URL)
	if exists, _ := h.store.Exists(r.Context(), albumID); exists {
		jsonOK(w, map[string]string{"albumId": albumID, "status": "done"}, http.StatusOK)
		return
	}

	jobID, err := h.queue.Enqueue(r.Context(), req.URL)
	if err != nil {
		jsonError(w, "failed to enqueue job", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]string{"jobId": jobID, "albumId": albumID, "status": "pending"}, http.StatusAccepted)
}

// GET /albums
func (h *handler) getAlbums(w http.ResponseWriter, r *http.Request) {
	albums, err := h.store.Albums(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	if albums == nil {
		albums = []store.AlbumSummary{}
	}
	uid := userIDFromCtx(r.Context())
	favs, _ := h.store.FavoriteAlbumIDs(r.Context(), uid)

	type item struct {
		ID               string   `json:"id"`
		Title            string   `json:"title"`
		Platform         string   `json:"platform"`
		Year             int      `json:"year"`
		AlbumType        string   `json:"albumType"`
		TrackCount       int      `json:"trackCount"`
		TotalDurationSec int      `json:"totalDurationSec"`
		CoverThumbURL    string   `json:"coverThumbUrl"`
		CoverURLs        []string `json:"coverUrls"`
		IsFavorite       bool     `json:"isFavorite"`
	}
	out := make([]item, len(albums))
	for i, a := range albums {
		urls := a.CoverURLs
		if urls == nil {
			urls = []string{}
		}
		out[i] = item{a.ID, a.Title, a.Platform, a.Year, a.AlbumType, a.TrackCount, a.TotalDurationSec, a.CoverThumbURL, urls, favs[a.ID]}
	}
	jsonOK(w, out, http.StatusOK)
}

// GET /albums/{id}
func (h *handler) getAlbum(w http.ResponseWriter, r *http.Request) {
	a, err := h.store.Album(r.Context(), r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		jsonError(w, "album not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}

	type cover struct {
		URL      string `json:"url"`
		Width    int    `json:"width"`
		Height   int    `json:"height"`
		ThumbURL string `json:"thumbUrl"`
	}
	type track struct {
		ID          string `json:"id"`
		Index       int    `json:"index"`
		Name        string `json:"name"`
		DurationSec int    `json:"durationSec"`
		SizeBytes   int64  `json:"sizeBytes"`
		StreamURL   string `json:"streamUrl"`
		DownloadURL string `json:"downloadUrl"`
		PageURL     string `json:"pageUrl"`
		Scraped     bool   `json:"scraped"`
		Downloaded  bool   `json:"downloaded"`
		IsFavorite  bool   `json:"isFavorite"`
	}
	type comment struct {
		Author   string `json:"author"`
		Body     string `json:"body"`
		PostedAt string `json:"postedAt"`
	}

	uid := userIDFromCtx(r.Context())
	trackFavs, _ := h.store.FavoriteTrackIDs(r.Context(), uid)

	tracks := make([]track, len(a.Tracks))
	for i, t := range a.Tracks {
		tracks[i] = track{
			ID:          t.ID,
			Index:       t.Index,
			Name:        t.Name,
			DurationSec: t.DurationSec,
			SizeBytes:   t.SizeBytes,
			StreamURL:   "/tracks/" + t.ID + "/stream",
			DownloadURL: "/tracks/" + t.ID + "/download",
			PageURL:     t.PageURL,
			Scraped:     t.MP3URL != "",
			Downloaded:  t.LocalPath != "",
			IsFavorite:  trackFavs[t.ID],
		}
	}
	covers := make([]cover, len(a.Covers))
	for i, c := range a.Covers {
		covers[i] = cover{c.URL, c.Width, c.Height, c.ThumbURL}
	}
	comments := make([]comment, len(a.Comments))
	for i, c := range a.Comments {
		comments[i] = comment{c.Author, c.Body, c.PostedAt.Format("2006-01-02T15:04:05Z")}
	}

	isFav := false
	if uid != "" {
		favs, _ := h.store.FavoriteAlbumIDs(r.Context(), uid)
		isFav = favs[r.PathValue("id")]
	}

	jsonOK(w, map[string]any{
		"id":            r.PathValue("id"),
		"sourceUrl":     a.SourceURL,
		"title":         a.Title,
		"altTitle":      a.AltTitle,
		"platform":      a.Platform,
		"year":          a.Year,
		"developer":     a.Developer,
		"publisher":     a.Publisher,
		"catalogNumber": a.CatalogNumber,
		"albumType":     a.AlbumType,
		"description":   a.Description,
		"covers":        covers,
		"tracks":        tracks,
		"comments":      comments,
		"isFavorite":    isFav,
	}, http.StatusOK)
}

// GET /albums/downloaded — albums with at least one locally-downloaded track.
func (h *handler) getDownloadedAlbums(w http.ResponseWriter, r *http.Request) {
	albums, err := h.store.AlbumsWithDownloads(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	type result struct {
		store.DownloadedAlbum
		DiskBytes int64 `json:"diskBytes"`
	}
	out := make([]result, 0, len(albums))
	for _, a := range albums {
		var diskBytes int64
		for _, p := range a.LocalPaths {
			if fi, err := os.Stat(p); err == nil {
				diskBytes += fi.Size()
			}
		}
		out = append(out, result{DownloadedAlbum: a, DiskBytes: diskBytes})
	}
	jsonOK(w, out, http.StatusOK)
}

// DELETE /albums/{id}/local — deletes local audio files and clears local_path in DB.
func (h *handler) deleteAlbumLocal(w http.ResponseWriter, r *http.Request) {
	albumID := r.PathValue("id")
	paths, err := h.store.ClearAlbumLocalPaths(r.Context(), albumID)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	deleted := 0
	for _, p := range paths {
		if os.Remove(p) == nil {
			deleted++
		}
	}
	jsonOK(w, map[string]int{"deleted": deleted}, http.StatusOK)
}

// DELETE /albums/{id} — removes the album entirely: DB rows (tracks, covers,
// comments, scrape jobs, history) and its files on disk (covers, downloaded mp3s).
func (h *handler) deleteAlbum(w http.ResponseWriter, r *http.Request) {
	albumID := r.PathValue("id")
	if err := h.store.DeleteAlbum(r.Context(), albumID); errors.Is(err, store.ErrNotFound) {
		jsonError(w, "album not found", http.StatusNotFound)
		return
	} else if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	_ = os.RemoveAll(filepath.Join(h.dataDir, albumID))
	jsonOK(w, map[string]string{"status": "deleted"}, http.StatusOK)
}
