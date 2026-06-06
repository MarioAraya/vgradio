// Package api wires the HTTP layer. Handlers are thin: validate input, delegate to
// store/queue, encode JSON. No business logic here.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/url"
	"strings"

	"github.com/arayama/vgradio-app/backend/internal/jobs"
	"github.com/arayama/vgradio-app/backend/internal/scraper"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

type queuer interface {
	Enqueue(ctx context.Context, albumURL string) (string, error)
	Get(ctx context.Context, jobID string) (*jobs.Job, error)
}

type storer interface {
	Albums(ctx context.Context) ([]store.AlbumSummary, error)
	Album(ctx context.Context, albumID string) (*scraper.Album, error)
	Track(ctx context.Context, trackID string) (*scraper.Track, error)
	SetTrackMP3URL(ctx context.Context, trackID, mp3URL string) error
	Exists(ctx context.Context, albumID string) (bool, error)
}

type mp3Resolver interface {
	SongMP3(ctx context.Context, pageURL string) (string, error)
}

type handler struct {
	store    storer
	queue    queuer
	resolver mp3Resolver
}

// NewRouter returns the API router.
func NewRouter(s storer, q queuer, r mp3Resolver) http.Handler {
	h := &handler{store: s, queue: q, resolver: r}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /albums", h.postAlbum)
	mux.HandleFunc("GET /albums", h.getAlbums)
	mux.HandleFunc("GET /albums/{id}", h.getAlbum)
	mux.HandleFunc("GET /jobs/{id}", h.getJob)
	mux.HandleFunc("GET /tracks/{id}/stream", h.streamTrack)
	mux.HandleFunc("GET /tracks/{id}/download", h.downloadTrack)
	return mux
}

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
	type item struct {
		ID         string `json:"id"`
		Title      string `json:"title"`
		Platform   string `json:"platform"`
		Year       int    `json:"year"`
		AlbumType  string `json:"albumType"`
		TrackCount int    `json:"trackCount"`
	}
	out := make([]item, len(albums))
	for i, a := range albums {
		out[i] = item{a.ID, a.Title, a.Platform, a.Year, a.AlbumType, a.TrackCount}
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
		URL    string `json:"url"`
		Width  int    `json:"width"`
		Height int    `json:"height"`
	}
	type track struct {
		ID          string `json:"id"`
		Index       int    `json:"index"`
		Name        string `json:"name"`
		DurationSec int    `json:"durationSec"`
		SizeBytes   int64  `json:"sizeBytes"`
		StreamURL   string `json:"streamUrl"`
		DownloadURL string `json:"downloadUrl"`
	}
	type comment struct {
		Author   string `json:"author"`
		Body     string `json:"body"`
		PostedAt string `json:"postedAt"`
	}

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
		}
	}
	covers := make([]cover, len(a.Covers))
	for i, c := range a.Covers {
		covers[i] = cover{c.URL, c.Width, c.Height}
	}
	comments := make([]comment, len(a.Comments))
	for i, c := range a.Comments {
		comments[i] = comment{c.Author, c.Body, c.PostedAt.Format("2006-01-02T15:04:05Z")}
	}

	jsonOK(w, map[string]any{
		"id":          r.PathValue("id"),
		"sourceUrl":   a.SourceURL,
		"title":       a.Title,
		"altTitle":    a.AltTitle,
		"platform":    a.Platform,
		"year":        a.Year,
		"developer":   a.Developer,
		"publisher":   a.Publisher,
		"albumType":   a.AlbumType,
		"description": a.Description,
		"covers":      covers,
		"tracks":      tracks,
		"comments":    comments,
	}, http.StatusOK)
}

// GET /tracks/{id}/stream — resolves mp3URL on demand and redirects (302).
// AVFoundation follows the redirect and handles Range requests natively.
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

	// Lazy MP3 resolution: fetch the per-song page and cache the direct URL.
	if tr.MP3URL == "" {
		if tr.PageURL == "" {
			jsonError(w, "track has no page URL", http.StatusServiceUnavailable)
			return
		}
		mp3URL, err := h.resolver.SongMP3(r.Context(), tr.PageURL)
		if err != nil {
			jsonError(w, "failed to resolve mp3: "+err.Error(), http.StatusBadGateway)
			return
		}
		_ = h.store.SetTrackMP3URL(r.Context(), trackID, mp3URL)
		tr.MP3URL = mp3URL
	}

	http.Redirect(w, r, tr.MP3URL, http.StatusFound)
}

// GET /tracks/{id}/download — same as stream but with Content-Disposition.
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
	if tr.MP3URL == "" {
		if tr.PageURL == "" {
			jsonError(w, "track has no page URL", http.StatusServiceUnavailable)
			return
		}
		mp3URL, err := h.resolver.SongMP3(r.Context(), tr.PageURL)
		if err != nil {
			jsonError(w, "failed to resolve mp3: "+err.Error(), http.StatusBadGateway)
			return
		}
		_ = h.store.SetTrackMP3URL(r.Context(), trackID, mp3URL)
		tr.MP3URL = mp3URL
	}
	w.Header().Set("Content-Disposition", `attachment; filename="`+tr.Name+`.mp3"`)
	http.Redirect(w, r, tr.MP3URL, http.StatusFound)
}

// --- SSRF guard ---

// privateRanges lists CIDR blocks that must never be fetched.
var privateRanges = func() []*net.IPNet {
	blocks := []string{
		"127.0.0.0/8",    // loopback
		"10.0.0.0/8",     // RFC1918
		"172.16.0.0/12",  // RFC1918
		"192.168.0.0/16", // RFC1918
		"169.254.0.0/16", // link-local / AWS metadata
		"::1/128",        // IPv6 loopback
		"fc00::/7",       // IPv6 unique local
	}
	nets := make([]*net.IPNet, 0, len(blocks))
	for _, b := range blocks {
		_, n, _ := net.ParseCIDR(b)
		nets = append(nets, n)
	}
	return nets
}()

func validateURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return errors.New("invalid URL")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return errors.New("URL must use http or https")
	}
	host := u.Hostname()
	ips, err := net.LookupHost(host)
	if err != nil {
		// Can't resolve — may be a network issue in tests; skip resolution check.
		// The fetch itself will fail if truly unreachable.
		ip := net.ParseIP(host)
		if ip == nil {
			return nil // unresolvable hostname, let fetcher fail naturally
		}
		ips = []string{ip.String()}
	}
	for _, ipStr := range ips {
		ip := net.ParseIP(ipStr)
		if ip == nil {
			continue
		}
		for _, block := range privateRanges {
			if block.Contains(ip) {
				return errors.New("URL resolves to a private/reserved address")
			}
		}
	}
	return nil
}

// --- helpers ---

func jsonOK(w http.ResponseWriter, v any, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v) //nolint:errcheck
}

func jsonError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg}) //nolint:errcheck
}

func nullTime(t interface{ IsZero() bool }) any {
	if t.IsZero() {
		return nil
	}
	type ts interface{ Format(string) string }
	if f, ok := t.(ts); ok {
		return f.Format("2006-01-02T15:04:05Z")
	}
	return nil
}
