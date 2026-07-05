package api

import (
	"encoding/json"
	"net/http"
)

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
