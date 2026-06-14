// Package catalog manages the browseable album catalog scraped from the origin site.
package catalog

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
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

	mu          sync.Mutex
	progress    SyncProgress
	cfClearance string
}

// New creates a Syncer.
func New(st catalogStore, f fetcher, log *slog.Logger) *Syncer {
	return &Syncer{store: st, fetcher: f, log: log}
}

// SetCFClearance updates the Cloudflare clearance cookie used for catalog page fetches.
func (s *Syncer) SetCFClearance(v string) {
	s.mu.Lock()
	s.cfClearance = v
	s.mu.Unlock()
}

// Progress returns a snapshot of the current sync state.
func (s *Syncer) Progress() SyncProgress {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.progress
}

// Start kicks off a full background sync (all letters + consoles). Returns false if already running.
func (s *Syncer) Start(ctx context.Context) bool {
	s.mu.Lock()
	if s.progress.Running {
		s.mu.Unlock()
		return false
	}
	// total = A-Z/0-9 browse pages + console list + consoles (unknown until list scraped)
	total := len(browseLetters) + 1
	s.progress = SyncProgress{Running: true, Total: total, StartedAt: time.Now()}
	s.mu.Unlock()

	go func() {
		s.run(ctx)
	}()
	return true
}

// StartLetter kicks off a background sync for a single browse letter (with pagination).
// Returns false if a sync is already running.
func (s *Syncer) StartLetter(ctx context.Context, letter string) bool {
	s.mu.Lock()
	if s.progress.Running {
		s.mu.Unlock()
		return false
	}
	s.progress = SyncProgress{Running: true, Total: 0, StartedAt: time.Now()}
	s.mu.Unlock()

	go func() {
		defer func() {
			total, _ := s.store.CountCatalog(context.Background(), "", "", "")
			s.mu.Lock()
			now := time.Now()
			s.progress.Running = false
			s.progress.FinishedAt = &now
			s.progress.Entries = total
			s.mu.Unlock()
		}()
		if err := s.syncBrowseLetterAllPages(ctx, letter); err != nil {
			s.log.Warn("catalog: letter sync failed", "letter", letter, "err", err)
			s.mu.Lock(); s.progress.Errors++; s.mu.Unlock()
		}
		s.log.Info("catalog: letter sync complete", "letter", letter)
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
		n, _ := s.store.CountCatalog(ctx, "", "", "")
		s.mu.Lock(); s.progress.Done++; s.progress.Entries = n; s.mu.Unlock()
	}

	// 2. Console list — get console names + URLs.
	if ctx.Err() != nil {
		return
	}
	var consoleList []scraper.Console
	if err := s.syncConsoleList(ctx, &consoleList); err != nil {
		s.log.Warn("catalog: console list failed", "err", err)
		s.mu.Lock(); s.progress.Errors++; s.mu.Unlock()
	}
	s.mu.Lock(); s.progress.Done++; s.mu.Unlock()

	// 3. Per-console pages — scrape each console to get accurate platform data.
	if len(consoleList) > 0 {
		s.mu.Lock()
		s.progress.Total += len(consoleList)
		s.mu.Unlock()
		for _, c := range consoleList {
			if ctx.Err() != nil {
				return
			}
			if err := s.syncConsolePage(ctx, c); err != nil {
				s.log.Warn("catalog: console page failed", "console", c.Name, "err", err)
				s.mu.Lock(); s.progress.Errors++; s.mu.Unlock()
			}
			s.mu.Lock(); s.progress.Done++; s.mu.Unlock()
		}
	}

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

// curlGet fetches a URL using the system curl binary, bypassing Go's TLS fingerprint
// which Cloudflare detects and blocks on browse/catalog pages.
func curlGet(ctx context.Context, cfClearance, url string) ([]byte, error) {
	args := []string{
		"-sL", "--http1.1",
		"-A", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		"-H", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
		"-H", "Accept-Language: en-US,en;q=0.9",
		"--max-time", "30",
	}
	if cfClearance != "" {
		args = append(args, "-H", "Cookie: cf_clearance="+cfClearance)
	}
	args = append(args, url)
	out, err := exec.CommandContext(ctx, "curl", args...).Output()
	return out, err
}

func (s *Syncer) syncBrowsePage(ctx context.Context, pageURL string) error {
	html, err := curlGet(ctx, s.cfClearance, pageURL)
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

// syncBrowseLetterAllPages fetches all paginated pages for a single browse letter.
func (s *Syncer) syncBrowseLetterAllPages(ctx context.Context, letter string) error {
	for page := 1; ; page++ {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		pageURL := fmt.Sprintf("%s/game-soundtracks/browse/%s", baseURL, letter)
		if page > 1 {
			pageURL = fmt.Sprintf("%s?page=%d", pageURL, page)
		}
		html, err := curlGet(ctx, s.cfClearance, pageURL)
		if err != nil {
			return fmt.Errorf("page %d: %w", page, err)
		}
		entries, err := scraper.ParseBrowsePage(html, pageURL)
		if err != nil {
			return fmt.Errorf("page %d parse: %w", page, err)
		}
		if len(entries) == 0 {
			break
		}
		s.log.Info("catalog: browse page scraped", "letter", letter, "page", page, "entries", len(entries))
		if err := s.store.UpsertCatalogEntries(ctx, entries); err != nil {
			return err
		}
		n, _ := s.store.CountCatalog(ctx, "", "", "")
		s.mu.Lock()
		s.progress.Done++
		s.progress.Total = s.progress.Done + 1 // always show at least 1 more expected
		s.progress.Entries = n
		s.mu.Unlock()
		// Polite delay between pages.
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
	}
	return nil
}

func (s *Syncer) syncConsoleList(ctx context.Context, out *[]scraper.Console) error {
	html, err := curlGet(ctx, s.cfClearance, consoleList)
	if err != nil {
		return err
	}
	consoles, err := scraper.ParseConsoleList(html, consoleList)
	if err != nil {
		return err
	}
	s.log.Info("catalog: console list scraped", "consoles", len(consoles))
	if out != nil {
		*out = consoles
	}
	return s.store.UpsertConsoles(ctx, consoles)
}

func (s *Syncer) syncConsolePage(ctx context.Context, c scraper.Console) error {
	html, err := curlGet(ctx, s.cfClearance, c.URL)
	if err != nil {
		return err
	}
	entries, err := scraper.ParseConsoleAlbums(html, c.URL)
	if err != nil {
		return err
	}
	// Override platform with the canonical console name so filtering works exactly.
	for i := range entries {
		entries[i].Platform = c.Name
	}
	s.log.Info("catalog: console page scraped", "console", c.Name, "entries", len(entries))
	return s.store.UpsertCatalogEntries(ctx, entries)
}
