// Package jobs manages the async scrape queue.
// A job fetches an album page, parses it, downloads covers, and persists via store.
// MP3 URL resolution is deferred to streaming time (lazy, per-track).
package jobs

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/imageutil"
	"github.com/arayama/vgradio-app/backend/internal/scraper"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

// Status represents the lifecycle state of a scrape job.
type Status string

const (
	StatusPending Status = "pending"
	StatusRunning Status = "running"
	StatusDone    Status = "done"
	StatusFailed  Status = "failed"
)

// Job is a single scrape task.
type Job struct {
	ID         string
	AlbumID    string
	AlbumURL   string
	Status     Status
	Error      string
	StartedAt  time.Time
	FinishedAt time.Time
}

// fetching is the subset of fetcher.Fetcher used by the queue.
type fetching interface {
	Get(ctx context.Context, url string) ([]byte, error)
	Download(ctx context.Context, url, destPath string) error
}

// storing is the subset of store.Store used by the queue.
type storing interface {
	Exists(ctx context.Context, albumID string) (bool, error)
	SaveAlbum(ctx context.Context, album *scraper.Album) (string, error)
}

// Queue is a bounded worker pool that processes scrape jobs.
type Queue struct {
	store   storing
	fetcher fetching
	dataDir string
	ch      chan *Job
	mu      sync.RWMutex
	jobs    map[string]*Job
}

// NewQueue creates a Queue. workers controls the worker pool size.
func NewQueue(s storing, f fetching, dataDir string, workers int) *Queue {
	if workers <= 0 {
		workers = 4
	}
	return &Queue{
		store:   s,
		fetcher: f,
		dataDir: dataDir,
		ch:      make(chan *Job, 64),
		jobs:    make(map[string]*Job),
	}
}

// Start launches the worker goroutines. Blocks until ctx is cancelled.
// Run as: go q.Start(ctx)
func (q *Queue) Start(ctx context.Context) {
	// Drain channel until ctx done.
	for {
		select {
		case j := <-q.ch:
			go q.process(ctx, j)
		case <-ctx.Done():
			return
		}
	}
}

// Enqueue adds a new scrape job for albumURL and returns the jobID immediately.
// The actual scraping happens asynchronously via the worker pool.
func (q *Queue) Enqueue(_ context.Context, albumURL string) (string, error) {
	j := &Job{
		ID:       newID(),
		AlbumURL: albumURL,
		Status:   StatusPending,
	}
	q.mu.Lock()
	q.jobs[j.ID] = j
	q.mu.Unlock()

	q.ch <- j
	return j.ID, nil
}

// Get returns the current state of a job. Returns an error if jobID is unknown.
func (q *Queue) Get(_ context.Context, jobID string) (*Job, error) {
	q.mu.RLock()
	j, ok := q.jobs[jobID]
	q.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("jobs: unknown job %q", jobID)
	}
	// Return a copy so callers can't race on the struct.
	q.mu.RLock()
	cp := *j
	q.mu.RUnlock()
	return &cp, nil
}

func (q *Queue) process(ctx context.Context, j *Job) {
	q.setStatus(j.ID, StatusRunning, "", time.Now(), time.Time{})

	albumID, err := q.run(ctx, j.AlbumURL)
	if err != nil {
		q.setStatus(j.ID, StatusFailed, err.Error(), time.Time{}, time.Now())
		return
	}
	q.mu.Lock()
	q.jobs[j.ID].AlbumID = albumID
	q.mu.Unlock()
	q.setStatus(j.ID, StatusDone, "", time.Time{}, time.Now())
}

// run does the actual work for one job. Returns the albumID on success.
func (q *Queue) run(ctx context.Context, albumURL string) (string, error) {
	albumID := store.AlbumID(albumURL)

	// Cache hit: album already scraped → nothing to do.
	if exists, err := q.store.Exists(ctx, albumID); err != nil {
		return "", fmt.Errorf("exists check: %w", err)
	} else if exists {
		return albumID, nil
	}

	// Fetch + parse album page.
	html, err := q.fetcher.Get(ctx, albumURL)
	if err != nil {
		return "", fmt.Errorf("fetch album page: %w", err)
	}
	album, err := scraper.ParseAlbum(html, albumURL)
	if err != nil {
		return "", fmt.Errorf("parse album: %w", err)
	}

	// Download covers to dataDir/<albumID>/covers/.
	// Original saved as cover_N_orig.ext; display (resized ≤400px) as cover_N.ext.
	// The API serves the display version; /albums/:id/covers.zip serves originals.
	coverDir := filepath.Join(q.dataDir, albumID, "covers")
	for i, c := range album.Covers {
		fileExt := ext(c.URL)
		origName := fmt.Sprintf("cover_%d_orig%s", i, fileExt)
		dispName := fmt.Sprintf("cover_%d%s", i, fileExt)
		origPath := filepath.Join(coverDir, origName)
		dispPath := filepath.Join(coverDir, dispName)

		if dlErr := q.fetcher.Download(ctx, c.URL, origPath); dlErr != nil {
			_ = dlErr
			continue
		}
		if resErr := imageutil.ResizeToDisplay(origPath, dispPath); resErr != nil {
			// Fallback: serve original as display if resize fails.
			_ = resErr
			_ = imageutil.CopyIfMissing(origPath, dispPath)
		}
		album.Covers[i].URL = "/covers/" + albumID + "/" + dispName
	}

	// Persist — MP3 URLs resolved lazily at stream time.
	id, err := q.store.SaveAlbum(ctx, album)
	if err != nil {
		return "", fmt.Errorf("save album: %w", err)
	}
	return id, nil
}

func (q *Queue) setStatus(id string, st Status, errMsg string, started, finished time.Time) {
	q.mu.Lock()
	defer q.mu.Unlock()
	j := q.jobs[id]
	j.Status = st
	j.Error = errMsg
	if !started.IsZero() {
		j.StartedAt = started
	}
	if !finished.IsZero() {
		j.FinishedAt = finished
	}
}

func newID() string {
	b := make([]byte, 8)
	rand.Read(b) //nolint:errcheck
	return hex.EncodeToString(b)
}

// ext extracts a file extension from a URL path, defaulting to ".jpg".
func ext(url string) string {
	for i := len(url) - 1; i >= 0 && url[i] != '/'; i-- {
		if url[i] == '.' {
			return url[i:]
		}
	}
	return ".jpg"
}
