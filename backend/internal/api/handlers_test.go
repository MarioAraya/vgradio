package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/api"
	"github.com/arayama/vgradio-app/backend/internal/fetcher"
	"github.com/arayama/vgradio-app/backend/internal/jobs"
	"github.com/arayama/vgradio-app/backend/internal/scraper"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

func setup(t *testing.T) (http.Handler, *store.Store, *jobs.Queue) {
	t.Helper()
	s := store.NewTestStore(t)
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 2})
	q := jobs.NewQueue(s, f, t.TempDir(), 2)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go q.Start(ctx)
	return api.NewRouter(s, q, f, t.TempDir()), s, q
}

func TestPostAlbums_MissingURL(t *testing.T) {
	router, _, _ := setup(t)
	body := `{}`
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/albums", strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, r)
	if w.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", w.Code)
	}
}

func TestPostAlbums_SSRFPrivateIP(t *testing.T) {
	router, _, _ := setup(t)
	for _, u := range []string{
		"http://127.0.0.1/evil",
		"http://192.168.1.1/evil",
		"http://10.0.0.1/evil",
		"http://169.254.169.254/latest/meta-data/", // AWS metadata
	} {
		body, _ := json.Marshal(map[string]string{"url": u})
		w := httptest.NewRecorder()
		r := httptest.NewRequest(http.MethodPost, "/albums", strings.NewReader(string(body)))
		r.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, r)
		if w.Code != http.StatusUnprocessableEntity {
			t.Errorf("url %s: status = %d, want 422", u, w.Code)
		}
	}
}

func TestPostAlbums_ReturnsJobID(t *testing.T) {
	router, _, _ := setup(t)
	body := `{"url":"https://downloads.khinsider.com/game-soundtracks/album/test"}`
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/albums", strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, r)
	if w.Code != http.StatusAccepted {
		t.Errorf("status = %d, want 202", w.Code)
	}
	var resp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["jobId"] == "" {
		t.Error("jobId missing from response")
	}
	if resp["status"] != "pending" {
		t.Errorf("status = %q, want pending", resp["status"])
	}
}

func TestGetJob_Unknown(t *testing.T) {
	router, _, _ := setup(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/jobs/nonexistent", nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", w.Code)
	}
}

func TestGetJob_Known(t *testing.T) {
	router, _, q := setup(t)
	jobID, _ := q.Enqueue(context.Background(), "https://downloads.khinsider.com/album/test2")

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/jobs/"+jobID, nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", w.Code)
	}
	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["jobId"] != jobID {
		t.Errorf("jobId = %v, want %q", resp["jobId"], jobID)
	}
	if resp["status"] == nil {
		t.Error("status field missing")
	}
}

func TestGetAlbums_Empty(t *testing.T) {
	router, _, _ := setup(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/albums", nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", w.Code)
	}
	var resp []any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp == nil {
		t.Error("expected empty JSON array, got null")
	}
}

func TestGetAlbum_NotFound(t *testing.T) {
	router, _, _ := setup(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/albums/nonexistent", nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", w.Code)
	}
}

func TestGetAlbum_Found(t *testing.T) {
	router, s, _ := setup(t)
	album := &scraper.Album{
		SourceURL: "https://downloads.khinsider.com/album/test-album",
		Title:     "Test Album",
		Platform:  "SNES",
		Year:      1995,
		Tracks: []scraper.Track{
			{Index: 1, Name: "Track One", DurationSec: 100, PageURL: "https://x.com/t1.mp3"},
		},
	}
	albumID, _ := s.SaveAlbum(context.Background(), album)

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/albums/"+albumID, nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", w.Code)
	}
	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["title"] != "Test Album" {
		t.Errorf("title = %v, want Test Album", resp["title"])
	}
	tracks, _ := resp["tracks"].([]any)
	if len(tracks) != 1 {
		t.Errorf("tracks count = %d, want 1", len(tracks))
	}
}

func TestStreamTrack_NotFound(t *testing.T) {
	router, _, _ := setup(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/tracks/9999/stream", nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", w.Code)
	}
}

func TestStreamTrack_RedirectsToMP3URL(t *testing.T) {
	// Serve a fake mp3.
	mp3Srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Write([]byte("FAKEMP3"))
	}))
	defer mp3Srv.Close()

	router, s, _ := setup(t)
	album := &scraper.Album{
		SourceURL: "https://downloads.khinsider.com/album/stream-test",
		Title:     "Stream Test",
		Platform:  "GC",
		Tracks: []scraper.Track{
			{Index: 1, Name: "Song", DurationSec: 60, PageURL: "https://x.com/song.mp3", MP3URL: mp3Srv.URL + "/track.mp3"},
		},
	}
	albumID, _ := s.SaveAlbum(context.Background(), album)

	// Get the track ID.
	a, _ := s.Album(context.Background(), albumID)
	trackID := a.Tracks[0].ID

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/tracks/"+trackID+"/stream", nil)
	router.ServeHTTP(w, r)

	// Expect redirect (302) to the direct mp3 URL.
	if w.Code != http.StatusFound {
		t.Errorf("status = %d, want 302", w.Code)
	}
	if loc := w.Header().Get("Location"); loc != mp3Srv.URL+"/track.mp3" {
		t.Errorf("Location = %q, want mp3 URL", loc)
	}
}

func waitStatus(t *testing.T, router http.Handler, jobID string, timeout time.Duration) string {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		w := httptest.NewRecorder()
		r := httptest.NewRequest(http.MethodGet, "/jobs/"+jobID, nil)
		router.ServeHTTP(w, r)
		var resp map[string]any
		json.NewDecoder(w.Body).Decode(&resp)
		if st, _ := resp["status"].(string); st == "done" || st == "failed" {
			return st
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("job %s did not finish within %v", jobID, timeout)
	return ""
}
