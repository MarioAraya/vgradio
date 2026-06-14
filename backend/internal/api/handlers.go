// Package api wires the HTTP layer. Handlers are thin: validate input, delegate to
// store/queue, encode JSON. No business logic here.
package api

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/arayama/vgradio-app/backend/internal/catalog"
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
	TrackAlbumID(ctx context.Context, trackID string) (string, error)
	SetTrackMP3URL(ctx context.Context, trackID, mp3URL string) error
	SetTrackLocalPath(ctx context.Context, trackID, localPath string) error
	Exists(ctx context.Context, albumID string) (bool, error)
	LibraryStats(ctx context.Context) (store.LibraryStats, error)
	AlbumsWithDownloads(ctx context.Context) ([]store.DownloadedAlbum, error)
	ClearAlbumLocalPaths(ctx context.Context, albumID string) ([]string, error)
	PendingTracks(ctx context.Context) ([]store.PendingTrack, error)
	SearchCatalog(ctx context.Context, q, platform, letter string, offset, limit int) ([]scraper.CatalogEntry, error)
	CountCatalog(ctx context.Context, q, platform, letter string) (int, error)
	Consoles(ctx context.Context) ([]scraper.Console, error)
	RecordPlay(ctx context.Context, trackID, albumID string) error
	RecentHistory(ctx context.Context, limit int) ([]store.HistoryEntry, error)
}

type trackFetcher interface {
	SongMP3(ctx context.Context, pageURL string) (string, error)
	Download(ctx context.Context, url, destPath string) error
	SetCFClearance(v string)
}

type catalogSyncer interface {
	Start(ctx context.Context) bool
	Progress() catalog.SyncProgress
}

type handler struct {
	store   storer
	queue   queuer
	fetcher trackFetcher
	syncer  catalogSyncer
	dataDir string
}

// NewRouter returns the API router. dataDir is the root for downloaded files.
func NewRouter(s storer, q queuer, f trackFetcher, syn catalogSyncer, dataDir string) http.Handler {
	h := &handler{store: s, queue: q, fetcher: f, syncer: syn, dataDir: dataDir}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /albums", h.postAlbum)
	mux.HandleFunc("GET /albums", h.getAlbums)
	mux.HandleFunc("GET /albums/{id}", h.getAlbum)
	mux.HandleFunc("GET /jobs/{id}", h.getJob)
	mux.HandleFunc("POST /albums/{id}/scrape-tracks", h.scrapeAlbumTracks)
	mux.HandleFunc("GET /tracks/{id}/stream", h.streamTrack)
	mux.HandleFunc("GET /tracks/{id}/resolve", h.resolveTrackURL)
	mux.HandleFunc("GET /tracks/{id}/download", h.downloadTrack)
	mux.HandleFunc("POST /tracks/{id}/fetch", h.fetchTrackLocal)
	mux.HandleFunc("POST /catalog/sync", h.postCatalogSync)
	mux.HandleFunc("GET /catalog/sync", h.getCatalogSync)
	mux.HandleFunc("GET /catalog", h.getCatalog)
	mux.HandleFunc("GET /catalog/consoles", h.getCatalogConsoles)
	mux.HandleFunc("PUT /config/cf-clearance", h.putCFClearance)
	mux.HandleFunc("POST /history", h.postHistory)
	mux.HandleFunc("GET /history", h.getHistory)
	mux.HandleFunc("GET /albums/{id}/covers.zip", h.getCoversZip)
	mux.HandleFunc("GET /stats", h.getStats)
	mux.HandleFunc("GET /albums/downloaded", h.getDownloadedAlbums)
	mux.HandleFunc("DELETE /albums/{id}/local", h.deleteAlbumLocal)
	mux.HandleFunc("POST /scrape/pending", h.scrapeAllPending)
	// Serve downloaded cover images.
	// URL pattern: /covers/<albumID>/<filename>
	// File on disk:  <dataDir>/<albumID>/covers/<filename>
	mux.HandleFunc("/covers/", func(w http.ResponseWriter, r *http.Request) {
		// strip leading /covers/
		rel := strings.TrimPrefix(r.URL.Path, "/covers/")
		parts := strings.SplitN(rel, "/", 2)
		if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
			http.NotFound(w, r)
			return
		}
		albumID, filename := parts[0], filepath.Base(parts[1])
		http.ServeFile(w, r, filepath.Join(dataDir, albumID, "covers", filename))
	})
	return cors(mux)
}

// cors wraps h with permissive CORS headers for local web client access.
func cors(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.ServeHTTP(w, r)
	})
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
		ID         string   `json:"id"`
		Title      string   `json:"title"`
		Platform   string   `json:"platform"`
		Year       int      `json:"year"`
		AlbumType  string   `json:"albumType"`
		TrackCount int      `json:"trackCount"`
		CoverURLs  []string `json:"coverUrls"`
	}
	out := make([]item, len(albums))
	for i, a := range albums {
		urls := a.CoverURLs
		if urls == nil {
			urls = []string{}
		}
		out[i] = item{a.ID, a.Title, a.Platform, a.Year, a.AlbumType, a.TrackCount, urls}
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
		Scraped     bool   `json:"scraped"`    // mp3_url resolved and cached
		Downloaded  bool   `json:"downloaded"` // file on local disk
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
			Scraped:     t.MP3URL != "",
			Downloaded:  t.LocalPath != "",
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

// POST /catalog/sync — starts a background catalog sync. 202 if started, 409 if already running.
func (h *handler) postCatalogSync(w http.ResponseWriter, r *http.Request) {
	if started := h.syncer.Start(context.Background()); !started {
		jsonError(w, "sync already running", http.StatusConflict)
		return
	}
	jsonOK(w, map[string]string{"status": "started"}, http.StatusAccepted)
}

// GET /catalog/sync — returns sync progress.
func (h *handler) getCatalogSync(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, h.syncer.Progress(), http.StatusOK)
}

// GET /catalog?q=&platform=&letter=&offset=&limit= — search/browse catalog entries.
func (h *handler) getCatalog(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	search := q.Get("q")
	platform := q.Get("platform")
	letter := q.Get("letter")
	offset, _ := strconv.Atoi(q.Get("offset"))
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	entries, err := h.store.SearchCatalog(r.Context(), search, platform, letter, offset, limit)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	total, err := h.store.CountCatalog(r.Context(), search, platform, letter)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}

	type item struct {
		Title     string `json:"title"`
		SourceURL string `json:"sourceUrl"`
		Platform  string `json:"platform"`
		Year      int    `json:"year"`
	}
	items := make([]item, len(entries))
	for i, e := range entries {
		items[i] = item{e.Title, e.SourceURL, e.Platform, e.Year}
	}
	jsonOK(w, map[string]any{
		"total":  total,
		"offset": offset,
		"limit":  limit,
		"items":  items,
	}, http.StatusOK)
}

// GET /catalog/consoles — returns all consoles ordered by album count.
func (h *handler) getCatalogConsoles(w http.ResponseWriter, r *http.Request) {
	consoles, err := h.store.Consoles(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	type item struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		URL        string `json:"url"`
		AlbumCount int    `json:"albumCount"`
	}
	items := make([]item, len(consoles))
	for i, c := range consoles {
		items[i] = item{c.Slug, c.Name, c.URL, c.AlbumCount}
	}
	jsonOK(w, items, http.StatusOK)
}

// PUT /config/cf-clearance — sets the Cloudflare clearance cookie at runtime.
func (h *handler) putCFClearance(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Value string `json:"value"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Value == "" {
		jsonError(w, "missing value", http.StatusBadRequest)
		return
	}
	h.fetcher.SetCFClearance(body.Value)
	jsonOK(w, map[string]string{"status": "ok"}, http.StatusOK)
}

// GET /albums/{id}/covers.zip — streams a ZIP of original cover images.
// Prefers cover_N_orig.* files (new albums); falls back to cover_N.* (old albums).
func (h *handler) getCoversZip(w http.ResponseWriter, r *http.Request) {
	albumID := r.PathValue("id")
	coverDir := filepath.Join(h.dataDir, albumID, "covers")

	entries, err := os.ReadDir(coverDir)
	if err != nil {
		jsonError(w, "album covers not found", http.StatusNotFound)
		return
	}

	// Collect files to zip: prefer _orig variants, fall back to display.
	type entry struct{ name, path string }
	origMap := map[string]string{} // base → orig path
	dispMap := map[string]string{} // base → display path

	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		fullPath := filepath.Join(coverDir, name)
		if strings.Contains(name, "_orig") {
			// strip _orig from the zip filename so it's clean
			clean := strings.Replace(name, "_orig", "", 1)
			origMap[clean] = fullPath
		} else {
			dispMap[name] = fullPath
		}
	}

	var files []entry
	for name, path := range origMap {
		files = append(files, entry{name, path})
	}
	if len(files) == 0 {
		for name, path := range dispMap {
			files = append(files, entry{name, path})
		}
	}
	if len(files) == 0 {
		jsonError(w, "no covers found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s-covers.zip"`, albumID))

	zw := zip.NewWriter(w)
	defer zw.Close()

	for _, f := range files {
		fw, err := zw.Create(f.name)
		if err != nil {
			continue
		}
		src, err := os.Open(f.path)
		if err != nil {
			continue
		}
		io.Copy(fw, src) //nolint:errcheck
		src.Close()
	}
}

// POST /history — records a track play event.
func (h *handler) postHistory(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TrackID string `json:"trackId"`
		AlbumID string `json:"albumId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.TrackID == "" || body.AlbumID == "" {
		jsonError(w, "trackId and albumId required", http.StatusBadRequest)
		return
	}
	if err := h.store.RecordPlay(r.Context(), body.TrackID, body.AlbumID); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /history?limit=N — returns recent play history.
func (h *handler) getHistory(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	entries, err := h.store.RecentHistory(r.Context(), limit)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, entries, http.StatusOK)
}

// GET /stats — library aggregate counts.
func (h *handler) getStats(w http.ResponseWriter, r *http.Request) {
	st, err := h.store.LibraryStats(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, st, http.StatusOK)
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
