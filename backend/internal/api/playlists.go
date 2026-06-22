package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/arayama/vgradio-app/backend/internal/auth"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

// GET /playlists — list playlists for the authenticated user + public playlists.
// Unauthenticated callers get only public playlists.
func (h *handler) getPlaylists(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	list, err := h.store.ListPlaylists(r.Context(), uid)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, list, http.StatusOK)
}

// POST /playlists — create a new playlist.
func (h *handler) postPlaylist(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		IsPublic    bool   `json:"isPublic"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, "invalid request body", http.StatusBadRequest)
		return
	}
	if body.Name == "" {
		jsonError(w, "name is required", http.StatusBadRequest)
		return
	}
	id, err := auth.NewID()
	if err != nil {
		jsonError(w, "failed to generate id", http.StatusInternalServerError)
		return
	}
	pl, err := h.store.CreatePlaylist(r.Context(), id, uid, body.Name, body.Description, body.IsPublic)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, pl, http.StatusCreated)
}

// GET /playlists/{id} — get playlist detail.
// Returns 403 for private playlists belonging to another user.
func (h *handler) getPlaylist(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := userIDFromCtx(r.Context())

	pl, err := h.store.GetPlaylist(r.Context(), id)
	if errors.Is(err, store.ErrPlaylistNotFound) {
		jsonError(w, "playlist not found", http.StatusNotFound)
		return
	}
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	if !pl.IsPublic && pl.OwnerID != uid {
		jsonError(w, "forbidden", http.StatusForbidden)
		return
	}
	jsonOK(w, pl, http.StatusOK)
}

// PATCH /playlists/{id} — update name, description, isPublic.
func (h *handler) patchPlaylist(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := userIDFromCtx(r.Context())

	if err := h.checkPlaylistOwner(r, id, uid); err != nil {
		writePlaylistOwnerError(w, err)
		return
	}

	pl, err := h.store.GetPlaylist(r.Context(), id)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}

	var body struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		IsPublic    *bool   `json:"isPublic"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	name := pl.Name
	desc := pl.Description
	pub := pl.IsPublic
	if body.Name != nil {
		name = *body.Name
	}
	if body.Description != nil {
		desc = *body.Description
	}
	if body.IsPublic != nil {
		pub = *body.IsPublic
	}
	if name == "" {
		jsonError(w, "name cannot be empty", http.StatusBadRequest)
		return
	}

	if err := h.store.UpdatePlaylist(r.Context(), id, name, desc, pub); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /playlists/{id} — delete a playlist.
func (h *handler) deletePlaylist(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := userIDFromCtx(r.Context())

	if err := h.checkPlaylistOwner(r, id, uid); err != nil {
		writePlaylistOwnerError(w, err)
		return
	}
	if err := h.store.DeletePlaylist(r.Context(), id); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// POST /playlists/{id}/tracks — add a track to the playlist.
func (h *handler) postPlaylistTrack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := userIDFromCtx(r.Context())

	if err := h.checkPlaylistOwner(r, id, uid); err != nil {
		writePlaylistOwnerError(w, err)
		return
	}

	var body struct {
		TrackID string `json:"trackId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.TrackID == "" {
		jsonError(w, "trackId is required", http.StatusBadRequest)
		return
	}

	if err := h.store.AddTrackToPlaylist(r.Context(), id, body.TrackID); errors.Is(err, store.ErrTrackAlreadyInPlaylist) {
		jsonError(w, "track already in playlist", http.StatusConflict)
		return
	} else if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /playlists/{id}/tracks/{trackId} — remove a track from the playlist.
func (h *handler) deletePlaylistTrack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	trackID := r.PathValue("trackId")
	uid := userIDFromCtx(r.Context())

	if err := h.checkPlaylistOwner(r, id, uid); err != nil {
		writePlaylistOwnerError(w, err)
		return
	}
	if err := h.store.RemoveTrackFromPlaylist(r.Context(), id, trackID); errors.Is(err, store.ErrNotFound) {
		jsonError(w, "track not in playlist", http.StatusNotFound)
		return
	} else if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// PUT /playlists/{id}/tracks/reorder — reorder tracks.
func (h *handler) putPlaylistReorder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := userIDFromCtx(r.Context())

	if err := h.checkPlaylistOwner(r, id, uid); err != nil {
		writePlaylistOwnerError(w, err)
		return
	}

	var items []store.ReorderItem
	if err := json.NewDecoder(r.Body).Decode(&items); err != nil || len(items) == 0 {
		jsonError(w, "items array required", http.StatusBadRequest)
		return
	}
	if err := h.store.ReorderPlaylistTracks(r.Context(), id, items); err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// checkPlaylistOwner verifies the playlist exists and uid is the owner.
func (h *handler) checkPlaylistOwner(r *http.Request, playlistID, uid string) error {
	ownerID, err := h.store.PlaylistOwner(r.Context(), playlistID)
	if err != nil {
		return err
	}
	if ownerID != uid {
		return errForbidden
	}
	return nil
}

var errForbidden = errors.New("forbidden")

func writePlaylistOwnerError(w http.ResponseWriter, err error) {
	if errors.Is(err, store.ErrPlaylistNotFound) {
		jsonError(w, "playlist not found", http.StatusNotFound)
	} else if errors.Is(err, errForbidden) {
		jsonError(w, "forbidden", http.StatusForbidden)
	} else {
		jsonError(w, "store error", http.StatusInternalServerError)
	}
}
