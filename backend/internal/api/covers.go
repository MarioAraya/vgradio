package api

import (
	"archive/zip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

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
