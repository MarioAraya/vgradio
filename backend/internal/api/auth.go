package api

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/auth"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

// --- rate limiter for login (max 10 attempts / IP / minute) ---

type rateLimiter struct {
	mu   sync.Mutex
	hits map[string][]time.Time
}

var loginLimiter = &rateLimiter{hits: map[string][]time.Time{}}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	cutoff := time.Now().Add(-time.Minute)
	var recent []time.Time
	for _, t := range rl.hits[ip] {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	if len(recent) >= 10 {
		rl.hits[ip] = recent
		return false
	}
	rl.hits[ip] = append(recent, time.Now())
	return true
}

// setSessionCookie creates a session in the DB and writes the sid cookie to w.
func (h *handler) setSessionCookie(ctx context.Context, w http.ResponseWriter, userID string) error {
	sid, err := auth.NewID()
	if err != nil {
		return err
	}
	expires := time.Now().Add(30 * 24 * time.Hour)
	if err := h.store.CreateSession(ctx, sid, userID, expires); err != nil {
		return err
	}
	http.SetCookie(w, &http.Cookie{
		Name:     "sid",
		Value:    sid,
		Path:     "/",
		Expires:  expires,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	return nil
}

// POST /auth/register
func (h *handler) postRegister(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, "invalid request body", http.StatusBadRequest)
		return
	}
	if err := auth.ValidateUsername(body.Username); err != nil {
		jsonError(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	if err := auth.ValidateEmail(body.Email); err != nil {
		jsonError(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	if err := auth.ValidatePassword(body.Password); err != nil {
		jsonError(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	id, err := auth.NewID()
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	if err := h.store.CreateUser(r.Context(), id, body.Username, body.Email, hash); err != nil {
		switch err {
		case store.ErrDuplicateUsername:
			jsonError(w, "username already in use", http.StatusConflict)
		case store.ErrDuplicateEmail:
			jsonError(w, "email already in use", http.StatusConflict)
		default:
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
		return
	}
	if err := h.setSessionCookie(r.Context(), w, id); err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]string{"id": id, "username": body.Username, "email": body.Email}, http.StatusCreated)
}

// POST /auth/login
func (h *handler) postLogin(w http.ResponseWriter, r *http.Request) {
	if !loginLimiter.allow(r.RemoteAddr) {
		jsonError(w, "too many login attempts, try again later", http.StatusTooManyRequests)
		return
	}
	var body struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Email == "" || body.Password == "" {
		jsonError(w, "email and password required", http.StatusBadRequest)
		return
	}
	u, hash, err := h.store.GetUserByEmail(r.Context(), body.Email)
	if err != nil || !auth.CheckPassword(hash, body.Password) {
		jsonError(w, "invalid email or password", http.StatusUnauthorized)
		return
	}
	if err := h.setSessionCookie(r.Context(), w, u.ID); err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]string{"id": u.ID, "username": u.Username, "email": u.Email}, http.StatusOK)
}

// POST /auth/logout
func (h *handler) postLogout(w http.ResponseWriter, r *http.Request) {
	sid := sessionIDFromCtx(r.Context())
	if sid != "" {
		_ = h.store.DeleteSession(r.Context(), sid)
	}
	http.SetCookie(w, &http.Cookie{Name: "sid", MaxAge: -1, Path: "/"})
	w.WriteHeader(http.StatusNoContent)
}

// GET /auth/me — returns the current user or null.
func (h *handler) getMe(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	if uid == "" {
		jsonOK(w, nil, http.StatusOK)
		return
	}
	u, err := h.store.GetUserByID(r.Context(), uid)
	if err != nil {
		jsonOK(w, nil, http.StatusOK)
		return
	}
	jsonOK(w, map[string]string{"id": u.ID, "username": u.Username, "email": u.Email}, http.StatusOK)
}

// POST /favorites/{id} — toggle album favorite for authenticated user.
func (h *handler) postFavorite(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	albumID := r.PathValue("id")
	favorited, err := h.store.ToggleFavorite(r.Context(), uid, albumID)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]bool{"favorited": favorited}, http.StatusOK)
}

// GET /favorites — list favorited albums for authenticated user.
func (h *handler) getFavorites(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	albums, err := h.store.GetFavorites(r.Context(), uid)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
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

// POST /favorites/tracks/{id} — toggle track favorite for authenticated user.
func (h *handler) postTrackFavorite(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	trackID := r.PathValue("id")
	favorited, err := h.store.ToggleTrackFavorite(r.Context(), uid, trackID)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]bool{"favorited": favorited}, http.StatusOK)
}

// GET /favorites/tracks — list favorited tracks for authenticated user.
func (h *handler) getFavoriteTracks(w http.ResponseWriter, r *http.Request) {
	uid := userIDFromCtx(r.Context())
	tracks, err := h.store.GetFavoriteTracks(r.Context(), uid)
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	type item struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		AlbumID     string `json:"albumId"`
		AlbumTitle  string `json:"albumTitle"`
		Platform    string `json:"platform"`
		Year        int    `json:"year"`
		DurationSec int    `json:"durationSec"`
		CoverURL    string `json:"coverUrl"`
	}
	out := make([]item, len(tracks))
	for i, t := range tracks {
		out[i] = item{t.ID, t.Name, t.AlbumID, t.AlbumTitle, t.Platform, t.Year, t.DurationSec, t.CoverURL}
	}
	jsonOK(w, out, http.StatusOK)
}

// POST /admin/reset-password — admin-only password reset via X-Admin-Key header.
func (h *handler) postAdminResetPassword(w http.ResponseWriter, r *http.Request) {
	secret := os.Getenv("ADMIN_SECRET")
	if secret == "" || r.Header.Get("X-Admin-Key") != secret {
		jsonError(w, "forbidden", http.StatusForbidden)
		return
	}
	var body struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Email == "" || body.Password == "" {
		jsonError(w, "email and password required", http.StatusBadRequest)
		return
	}
	if err := auth.ValidatePassword(body.Password); err != nil {
		jsonError(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	if err := h.store.ResetPassword(r.Context(), body.Email, hash); err != nil {
		if err == store.ErrUserNotFound {
			jsonError(w, "user not found", http.StatusNotFound)
			return
		}
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, map[string]string{"status": "ok"}, http.StatusOK)
}
