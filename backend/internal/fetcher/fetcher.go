// Package fetcher downloads files from the origin site with rate limiting and context support.
package fetcher

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

// Options configures a Fetcher.
type Options struct {
	// Delay is the minimum time between requests to the origin server.
	Delay time.Duration
	// MaxConcurrent limits parallel in-flight requests (0 defaults to 4).
	MaxConcurrent int
	// HTTPClient is optional; defaults to a client with a 30s timeout.
	HTTPClient *http.Client
	// CFClearance is the cf_clearance cookie value copied from a logged-in browser
	// session. Required to bypass Cloudflare on browse/catalog pages.
	CFClearance string
}

// Fetcher downloads pages and files with throttling and concurrency limiting.
type Fetcher struct {
	client      *http.Client
	delay       time.Duration
	sem         chan struct{}
	mu          sync.Mutex
	lastAt      time.Time
	cfClearance string
}

// New creates a Fetcher from Options.
func New(opts Options) *Fetcher {
	mc := opts.MaxConcurrent
	if mc <= 0 {
		mc = 4
	}
	client := opts.HTTPClient
	if client == nil {
		// Use default transport — khinsider/CF endpoints require HTTP/2 (respond with
		// H2 SETTINGS frames regardless of ALPN). Go's default client handles H2 correctly.
		// CF clearance cookie is the primary bypass mechanism.
		client = &http.Client{Timeout: 30 * time.Second}
	}
	return &Fetcher{
		client:      client,
		delay:       opts.Delay,
		sem:         make(chan struct{}, mc),
		cfClearance: opts.CFClearance,
	}
}

// SetCFClearance updates the Cloudflare clearance cookie at runtime.
func (f *Fetcher) SetCFClearance(v string) {
	f.mu.Lock()
	f.cfClearance = v
	f.mu.Unlock()
}

// Get fetches url and returns the raw response body.
func (f *Fetcher) Get(ctx context.Context, url string) ([]byte, error) {
	return f.get(ctx, url)
}

// SongMP3 fetches the per-song page at pageURL and returns the direct .mp3 URL.
func (f *Fetcher) SongMP3(ctx context.Context, pageURL string) (string, error) {
	body, err := f.get(ctx, pageURL)
	if err != nil {
		return "", fmt.Errorf("fetcher.SongMP3 %s: %w", pageURL, err)
	}
	mp3URL, err := scraper.ParseSongMP3(body)
	if err != nil {
		return "", fmt.Errorf("fetcher.SongMP3 parse %s: %w", pageURL, err)
	}
	return mp3URL, nil
}

// Download fetches url and writes the body to destPath, creating parent directories as needed.
func (f *Fetcher) Download(ctx context.Context, url, destPath string) error {
	body, err := f.get(ctx, url)
	if err != nil {
		return fmt.Errorf("fetcher.Download %s: %w", url, err)
	}
	if err := os.MkdirAll(filepath.Dir(destPath), 0o755); err != nil {
		return err
	}
	// Write atomically: temp file → rename.
	tmp := destPath + ".tmp"
	if err := os.WriteFile(tmp, body, 0o644); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, destPath)
}

// get acquires the semaphore, enforces the rate-limit delay, then performs a GET.
func (f *Fetcher) get(ctx context.Context, url string) ([]byte, error) {
	// Acquire concurrency slot.
	select {
	case f.sem <- struct{}{}:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	defer func() { <-f.sem }()

	// Throttle: sleep until delay has elapsed since last request.
	if f.delay > 0 {
		f.mu.Lock()
		wait := time.Until(f.lastAt.Add(f.delay))
		f.mu.Unlock()
		if wait > 0 {
			select {
			case <-time.After(wait):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")

	f.mu.Lock()
	cf := f.cfClearance
	f.mu.Unlock()
	if cf != "" {
		req.Header.Set("Cookie", "cf_clearance="+cf)
	}

	f.mu.Lock()
	f.lastAt = time.Now()
	f.mu.Unlock()

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d for %s", resp.StatusCode, url)
	}

	return io.ReadAll(resp.Body)
}
