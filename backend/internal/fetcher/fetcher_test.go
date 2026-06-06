package fetcher_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/fetcher"
)

// fakeSongPage returns a minimal song-page HTML with a direct mp3 URL.
func fakeSongPage(mp3URL string) string {
	return `<html><body>
<audio id="audio" controls preload="auto" src="` + mp3URL + `"></audio>
</body></html>`
}

func TestSongMP3_ExtractsURL(t *testing.T) {
	const wantMP3 = "https://cdn.example.com/audio/track01.mp3"

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(fakeSongPage(wantMP3)))
	}))
	defer srv.Close()

	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 1})
	got, err := f.SongMP3(context.Background(), srv.URL+"/song/track01.mp3")
	if err != nil {
		t.Fatalf("SongMP3: %v", err)
	}
	if got != wantMP3 {
		t.Errorf("SongMP3 = %q, want %q", got, wantMP3)
	}
}

func TestDownload_WritesFile(t *testing.T) {
	const content = "fake mp3 bytes 123"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Write([]byte(content))
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "track01.mp3")
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 1})
	if err := f.Download(context.Background(), srv.URL+"/audio/track01.mp3", dest); err != nil {
		t.Fatalf("Download: %v", err)
	}

	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read dest: %v", err)
	}
	if string(got) != content {
		t.Errorf("file content = %q, want %q", got, content)
	}
}

func TestDownload_ContextCancel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Never finishes writing — simulates a hanging server.
		<-r.Context().Done()
	}))
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	dest := filepath.Join(t.TempDir(), "track.mp3")
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 1})
	err := f.Download(ctx, srv.URL+"/audio/track.mp3", dest)
	if err == nil {
		t.Error("expected error on context cancel, got nil")
	}
}

func TestDownload_ServerError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not found", http.StatusNotFound)
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "track.mp3")
	f := fetcher.New(fetcher.Options{Delay: 0, MaxConcurrent: 1})
	err := f.Download(context.Background(), srv.URL+"/bad", dest)
	if err == nil {
		t.Error("expected error for 404 response, got nil")
	}
}

func TestDelay_ThrottlesRequests(t *testing.T) {
	var count atomic.Int32
	var times []time.Time
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		times = append(times, time.Now())
		count.Add(1)
		w.Write([]byte("ok"))
	}))
	defer srv.Close()

	const delay = 40 * time.Millisecond
	f := fetcher.New(fetcher.Options{Delay: delay, MaxConcurrent: 1})
	ctx := context.Background()

	dir := t.TempDir()
	for i := range 3 {
		dest := filepath.Join(dir, filepath.Join("f"+string(rune('0'+i))))
		if err := f.Download(ctx, srv.URL+"/file", dest); err != nil {
			t.Fatalf("Download %d: %v", i, err)
		}
	}

	if len(times) < 2 {
		t.Fatal("not enough requests")
	}
	for i := 1; i < len(times); i++ {
		gap := times[i].Sub(times[i-1])
		if gap < delay/2 {
			t.Errorf("gap between requests %d-%d = %v, want >= %v", i-1, i, gap, delay/2)
		}
	}
}
