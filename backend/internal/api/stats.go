package api

import "net/http"

// GET /stats — library aggregate counts.
func (h *handler) getStats(w http.ResponseWriter, r *http.Request) {
	st, err := h.store.LibraryStats(r.Context())
	if err != nil {
		jsonError(w, "store error", http.StatusInternalServerError)
		return
	}
	jsonOK(w, st, http.StatusOK)
}
