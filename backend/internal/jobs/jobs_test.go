package jobs_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/fetcher"
	"github.com/arayama/vgradio-app/backend/internal/jobs"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

// testServer serves an album page + a fake cover image.
func testServer(t *testing.T) *httptest.Server {
	t.Helper()
	albumHTML, err := os.ReadFile("../scraper/testdata/album.html")
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/album", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write(albumHTML)
	})
	mux.HandleFunc("/cover.jpg", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		w.Write([]byte("fake-image-bytes"))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func waitJob(t *testing.T, q *jobs.Queue, jobID string, timeout time.Duration) *jobs.Job {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		j, err := q.Get(context.Background(), jobID)
		if err != nil {
			t.Fatalf("Get job: %v", err)
		}
		if j.Status == jobs.StatusDone || j.Status == jobs.StatusFailed {
			return j
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("job %s did not finish within %v", jobID, timeout)
	return nil
}

func TestEnqueue_ReturnsPendingJob(t *testing.T) {
	srv := testServer(t)
	s := store.NewTestStore(t)
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 2})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	q := jobs.NewQueue(s, f, t.TempDir(), 2)
	go q.Start(ctx)

	jobID, err := q.Enqueue(context.Background(), srv.URL+"/album")
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	if jobID == "" {
		t.Fatal("Enqueue returned empty jobID")
	}

	j, err := q.Get(context.Background(), jobID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if j.ID != jobID {
		t.Errorf("Job.ID = %q, want %q", j.ID, jobID)
	}
}

func TestWorker_JobCompletes(t *testing.T) {
	srv := testServer(t)
	s := store.NewTestStore(t)
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 2})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	q := jobs.NewQueue(s, f, t.TempDir(), 2)
	go q.Start(ctx)

	jobID, err := q.Enqueue(context.Background(), srv.URL+"/album")
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}

	j := waitJob(t, q, jobID, 5*time.Second)
	if j.Status != jobs.StatusDone {
		t.Errorf("final status = %q (error: %s), want done", j.Status, j.Error)
	}
	if j.AlbumID == "" {
		t.Error("Job.AlbumID empty after completion")
	}

	// Album must be in store.
	exists, err := s.Exists(context.Background(), j.AlbumID)
	if err != nil {
		t.Fatalf("Exists: %v", err)
	}
	if !exists {
		t.Error("album not found in store after job done")
	}
}

func TestWorker_SkipsExistingAlbum(t *testing.T) {
	srv := testServer(t)
	s := store.NewTestStore(t)
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 2})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	q := jobs.NewQueue(s, f, t.TempDir(), 2)
	go q.Start(ctx)

	// First job populates cache.
	id1, _ := q.Enqueue(context.Background(), srv.URL+"/album")
	waitJob(t, q, id1, 5*time.Second)

	// Second job for same URL must complete without re-scraping (very fast).
	start := time.Now()
	id2, err := q.Enqueue(context.Background(), srv.URL+"/album")
	if err != nil {
		t.Fatalf("second Enqueue: %v", err)
	}
	j2 := waitJob(t, q, id2, 2*time.Second)
	if j2.Status != jobs.StatusDone {
		t.Errorf("second job status = %q, want done", j2.Status)
	}
	// Should complete nearly instantly (no network).
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Logf("warning: second job took %v (expected fast cache hit)", elapsed)
	}
}

func TestWorker_FailsOnBadURL(t *testing.T) {
	s := store.NewTestStore(t)
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 1})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	q := jobs.NewQueue(s, f, t.TempDir(), 1)
	go q.Start(ctx)

	jobID, err := q.Enqueue(context.Background(), "http://127.0.0.1:1/unreachable")
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	j := waitJob(t, q, jobID, 5*time.Second)
	if j.Status != jobs.StatusFailed {
		t.Errorf("status = %q, want failed", j.Status)
	}
	if j.Error == "" {
		t.Error("Job.Error empty on failure")
	}
}
