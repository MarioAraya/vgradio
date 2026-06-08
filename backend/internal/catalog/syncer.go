// Package catalog manages the browseable album catalog scraped from the origin site.
package catalog

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

const (
	baseURL     = "https://downloads.khinsider.com"
	consoleList = baseURL + "/console-list"
)

// browseLetters is the full set of browse-page suffixes.
var browseLetters = func() []string {
	letters := []string{"0-9"}
	for c := 'A'; c <= 'Z'; c++ {
		letters = append(letters, string(c))
	}
	return letters
}()

// SyncProgress describes the current state of a catalog sync.
type SyncProgress struct {
	Running   bool      `json:"running"`
	Total     int       `json:"total"`
	Done      int       `json:"done"`
	Errors    int       `json:"errors"`
	Entries   int       `json:"entries"`  // total catalog entries in DB
	Consoles  int       `json:"consoles"` // total console rows in DB
	StartedAt time.Time `json:"startedAt,omitempty"`
	FinishedAt *time.Time `json:"finishedAt,omitempty"`
}

// fetcher is the subset of fetcher.Fetcher used by the syncer.
type fetcher interface {
	Get(ctx context.Context, url string) ([]byte, error)
}

// catalogStore is the subset of store.Store used by the syncer.
type catalogStore interface {
	UpsertCatalogEntries(ctx context.Context, entries []scraper.CatalogEntry) error
	UpsertConsoles(ctx context.Context, consoles []scraper.Console) error
	CountCatalog(ctx context.Context, q, platform, letter string) (int, error)
	Consoles(ctx context.Context) ([]scraper.Console, error)
}

// Syncer orchestrates the catalog scrape.
type Syncer struct {
	store   catalogStore
	fetcher fetcher
	log     *slog.Logger

	mu       sync.Mutex
	progress SyncProgress
}

// New creates a Syncer.
func New(st catalogStore, f fetcher, log *slog.Logger) *Syncer {
	return &Syncer{store: st, fetcher: f, log: log}
}

// Progress returns a snapshot of the current sync state.
func (s *Syncer) Progress() SyncProgress {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.progress
}

// Start kicks off a background sync. If already running it returns false.
func (s *Syncer) Start(ctx context.Context) bool {
	s.mu.Lock()
	if s.progress.Running {
		s.mu.Unlock()
		return false
	}
	total := len(browseLetters) + 1 // browse pages + console list
	s.progress = SyncProgress{Running: true, Total: total, StartedAt: time.Now()}
	s.mu.Unlock()

	go func() {
		s.run(ctx)
	}()
	return true
}

func (s *Syncer) run(ctx context.Context) {
	defer func() {
		s.mu.Lock()
		now := time.Now()
		s.progress.Running = false
		s.progress.FinishedAt = &now
		s.mu.Unlock()
	}()

	// 1. Browse pages A-Z + 0-9.
	for _, letter := range browseLetters {
		if ctx.Err() != nil {
			return
		}
		url := fmt.Sprintf("%s/game-soundtracks/browse/%s", baseURL, letter)
		if err := s.syncBrowsePage(ctx, url); err != nil {
			s.log.Warn("catalog: browse page failed", "letter", letter, "err", err)
			s.mu.Lock(); s.progress.Errors++; s.mu.Unlock()
		}
		s.mu.Lock(); s.progress.Done++; s.mu.Unlock()
	}

	// 2. Console list.
	if ctx.Err() != nil {
		return
	}
	if err := s.syncConsoleList(ctx); err != nil {
		s.log.Warn("catalog: console list failed", "err", err)
		s.mu.Lock(); s.progress.Errors++; s.mu.Unlock()
	}
	s.mu.Lock(); s.progress.Done++; s.mu.Unlock()

	// Refresh counts.
	total, _ := s.store.CountCatalog(context.Background(), "", "", "")
	consoles, _ := s.store.Consoles(context.Background())
	s.mu.Lock()
	s.progress.Entries = total
	s.progress.Consoles = len(consoles)
	s.mu.Unlock()

	s.log.Info("catalog sync complete",
		"entries", total,
		"consoles", len(consoles),
		"errors", s.progress.Errors)
}

func (s *Syncer) syncBrowsePage(ctx context.Context, pageURL string) error {
	html, err := s.fetcher.Get(ctx, pageURL)
	if err != nil {
		return err
	}
	entries, err := scraper.ParseBrowsePage(html, pageURL)
	if err != nil {
		return err
	}
	s.log.Info("catalog: browse page scraped", "url", pageURL, "entries", len(entries))
	return s.store.UpsertCatalogEntries(ctx, entries)
}

func (s *Syncer) syncConsoleList(ctx context.Context) error {
	html, err := s.fetcher.Get(ctx, consoleList)
	if err != nil {
		return err
	}
	consoles, err := scraper.ParseConsoleList(html, consoleList)
	if err != nil {
		return err
	}
	s.log.Info("catalog: console list scraped", "consoles", len(consoles))
	return s.store.UpsertConsoles(ctx, consoles)
}
