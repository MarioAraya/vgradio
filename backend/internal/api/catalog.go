package api

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// POST /catalog/sync — starts a background catalog sync.
// Optional ?letter=S syncs only that browse letter (with pagination).
// 202 if started, 409 if already running.
func (h *handler) postCatalogSync(w http.ResponseWriter, r *http.Request) {
	letter := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("letter")))
	if letter != "" {
		if started := h.syncer.StartLetter(context.Background(), letter); !started {
			jsonError(w, "sync already running", http.StatusConflict)
			return
		}
		jsonOK(w, map[string]string{"status": "started", "letter": letter}, http.StatusAccepted)
		return
	}
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
		AlbumType string `json:"albumType"`
		Year      int    `json:"year"`
	}
	items := make([]item, len(entries))
	for i, e := range entries {
		items[i] = item{e.Title, e.SourceURL, e.Platform, e.AlbumType, e.Year}
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

// GET /catalog/top40 — returns the weekly Top 40 chart from khinsider.
func (h *handler) getTop40(w http.ResponseWriter, r *http.Request) {
	entries, err := h.syncer.Top40(r.Context())
	if err != nil {
		jsonError(w, "fetch error", http.StatusBadGateway)
		return
	}
	type item struct {
		Rank          int    `json:"rank"`
		Title         string `json:"title"`
		SourceURL     string `json:"sourceUrl"`
		CoverThumbURL string `json:"coverThumbUrl"`
	}
	items := make([]item, len(entries))
	for i, e := range entries {
		items[i] = item{e.Rank, e.Title, e.SourceURL, e.ThumbURL}
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
	h.syncer.SetCFClearance(body.Value)
	// Persist to disk so it survives a server restart — the syncer otherwise
	// only holds this cookie in memory and a weekly auto-sync would silently
	// fail against Cloudflare after any restart.
	if err := os.WriteFile(filepath.Join(h.dataDir, "cf_clearance.txt"), []byte(body.Value), 0o600); err != nil {
		jsonError(w, "saved in memory but failed to persist to disk", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]string{"status": "ok"}, http.StatusOK)
}
