package api

import (
	"encoding/json"
	"net/http"
	"strconv"
)

// POST /history — records a track play event for the current user (no-op if anonymous).
func (h *handler) postHistory(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TrackID string `json:"trackId"`
		AlbumID string `json:"albumId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.TrackID == "" || body.AlbumID == "" {
		jsonError(w, "trackId and albumId required", http.StatusBadRequest)
		return
	}
	uid := userIDFromCtx(r.Context())
	if err := h.store.RecordPlay(r.Context(), body.TrackID, body.AlbumID, uid); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /history?limit=N — returns recent play history for the authenticated user.
// Returns empty array for anonymous requests.
func (h *handler) getHistory(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	uid := userIDFromCtx(r.Context())
	entries, err := h.store.RecentHistory(r.Context(), limit, uid)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, entries, http.StatusOK)
}
