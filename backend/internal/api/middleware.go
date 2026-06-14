package api

import (
	"context"
	"net/http"
	"time"
)

type contextKey int

const (
	ctxUserID    contextKey = iota
	ctxSessionID contextKey = iota
)

func userIDFromCtx(ctx context.Context) string {
	v, _ := ctx.Value(ctxUserID).(string)
	return v
}

func sessionIDFromCtx(ctx context.Context) string {
	v, _ := ctx.Value(ctxSessionID).(string)
	return v
}

// authMiddleware reads the "sid" cookie, validates the session, and injects
// userID + sessionID into the request context. Continues as anonymous if absent/expired.
func (h *handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie("sid")
		if err != nil || cookie.Value == "" {
			next.ServeHTTP(w, r)
			return
		}
		sid := cookie.Value
		userID, expiresAt, err := h.store.GetSession(r.Context(), sid)
		if err != nil || time.Now().After(expiresAt) {
			http.SetCookie(w, &http.Cookie{Name: "sid", MaxAge: -1, Path: "/"})
			next.ServeHTTP(w, r)
			return
		}
		_ = h.store.RenewSession(r.Context(), sid, time.Now().Add(30*24*time.Hour))
		ctx := context.WithValue(r.Context(), ctxUserID, userID)
		ctx = context.WithValue(ctx, ctxSessionID, sid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// requireAuth returns 401 if the request has no authenticated user.
func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if userIDFromCtx(r.Context()) == "" {
			jsonError(w, "authentication required", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}
