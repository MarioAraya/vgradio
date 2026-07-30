package catalog

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

// fakeStore is an in-memory catalogStore for tests — no real DB or network involved.
type fakeStore struct {
	mu            sync.Mutex
	entries       []scraper.CatalogEntry
	consoles      []scraper.Console
	syncedLetters []string
}

func (f *fakeStore) UpsertCatalogEntries(_ context.Context, entries []scraper.CatalogEntry) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.entries = append(f.entries, entries...)
	return nil
}

func (f *fakeStore) UpsertConsoles(_ context.Context, consoles []scraper.Console) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.consoles = append(f.consoles, consoles...)
	return nil
}

func (f *fakeStore) CountCatalog(_ context.Context, _, _, _ string) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.entries), nil
}

func (f *fakeStore) Consoles(_ context.Context) ([]scraper.Console, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.consoles, nil
}

func (f *fakeStore) MarkLetterSynced(_ context.Context, letter string, _ int) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.syncedLetters = append(f.syncedLetters, letter)
	return nil
}

func silentLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

const oneAlbumHTML = `<html><body><table><tr>
	<td><a href="/game-soundtracks/album/test-1">Test Game</a></td>
	<td>SNES</td><td>12</td><td>Soundtrack</td><td>1995</td>
</tr></table></body></html>`

const emptyHTML = `<html><body>no albums here</body></html>`

const oneConsoleHTML = `<html><body>
	<a href="/game-soundtracks/nintendo-snes">Nintendo SNES (10)</a>
</body></html>`

func TestSyncBrowsePage_UpsertsParsedEntries(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		return []byte(oneAlbumHTML), nil
	}

	if err := s.syncBrowsePage(context.Background(), "https://downloads.khinsider.com/game-soundtracks/browse/A"); err != nil {
		t.Fatalf("syncBrowsePage: %v", err)
	}
	if len(fs.entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(fs.entries))
	}
	if fs.entries[0].Title != "Test Game" {
		t.Errorf("Title = %q, want Test Game", fs.entries[0].Title)
	}
}

func TestSyncBrowsePage_PropagatesFetchError(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	wantErr := errors.New("curl failed")
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		return nil, wantErr
	}

	err := s.syncBrowsePage(context.Background(), "https://downloads.khinsider.com/game-soundtracks/browse/A")
	if !errors.Is(err, wantErr) {
		t.Errorf("err = %v, want %v", err, wantErr)
	}
}

func TestSyncBrowseLetterAllPages_StopsOnEmptyPage(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	var calls int
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		calls++
		if calls == 1 {
			return []byte(oneAlbumHTML), nil
		}
		return []byte(emptyHTML), nil
	}

	if err := s.syncBrowseLetterAllPages(context.Background(), "A"); err != nil {
		t.Fatalf("syncBrowseLetterAllPages: %v", err)
	}
	if calls != 2 {
		t.Errorf("httpGet called %d times, want 2 (one page with entries, one empty stopping the loop)", calls)
	}
	if len(fs.entries) != 1 {
		t.Errorf("len(entries) = %d, want 1", len(fs.entries))
	}
}

func TestSyncConsoleList_PopulatesOutAndStore(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		return []byte(oneConsoleHTML), nil
	}

	var out []scraper.Console
	if err := s.syncConsoleList(context.Background(), &out); err != nil {
		t.Fatalf("syncConsoleList: %v", err)
	}
	if len(out) != 1 {
		t.Fatalf("len(out) = %d, want 1", len(out))
	}
	if len(fs.consoles) != 1 {
		t.Errorf("len(fs.consoles) = %d, want 1", len(fs.consoles))
	}
}

func TestSyncConsolePage_OverridesPlatformWithConsoleName(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		return []byte(oneAlbumHTML), nil
	}

	console := scraper.Console{Name: "Super Nintendo", Slug: "nintendo-snes", URL: "https://downloads.khinsider.com/game-soundtracks/nintendo-snes"}
	if err := s.syncConsolePage(context.Background(), console); err != nil {
		t.Fatalf("syncConsolePage: %v", err)
	}
	if len(fs.entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(fs.entries))
	}
	if fs.entries[0].Platform != "Super Nintendo" {
		t.Errorf("Platform = %q, want overridden to Super Nintendo", fs.entries[0].Platform)
	}
}

func TestStart_ReturnsFalseIfAlreadyRunning(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	block := make(chan struct{})
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		<-block
		return []byte(emptyHTML), nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if !s.Start(ctx) {
		t.Fatal("first Start = false, want true")
	}
	if s.Start(ctx) {
		t.Error("second Start = true while running, want false")
	}
	close(block)
	cancel()
}

func TestStartLetter_ReturnsFalseIfAlreadyRunning(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	block := make(chan struct{})
	s.httpGet = func(_ context.Context, _, _ string) ([]byte, error) {
		<-block
		return []byte(emptyHTML), nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if !s.StartLetter(ctx, "A") {
		t.Fatal("first StartLetter = false, want true")
	}
	if s.StartLetter(ctx, "B") {
		t.Error("second StartLetter = true while running, want false")
	}
	close(block)
	cancel()
}

func TestRun_CompletesAndUpdatesProgress(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	s.httpGet = func(_ context.Context, _, url string) ([]byte, error) {
		if strings.Contains(url, "console-list") {
			return []byte(emptyHTML), nil // no consoles: skips step 3
		}
		return []byte(emptyHTML), nil
	}

	if !s.Start(context.Background()) {
		t.Fatal("Start = false, want true")
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if !s.Progress().Running {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	p := s.Progress()
	if p.Running {
		t.Fatal("sync did not finish within timeout")
	}
	if p.FinishedAt == nil {
		t.Error("FinishedAt not set after completion")
	}
	if p.Errors != 0 {
		t.Errorf("Errors = %d, want 0 (all fetches succeeded)", p.Errors)
	}
}

func TestSetCFClearance_UsedInFetch(t *testing.T) {
	fs := &fakeStore{}
	s := New(fs, silentLogger())
	var gotClearance string
	s.httpGet = func(_ context.Context, cfClearance, _ string) ([]byte, error) {
		gotClearance = cfClearance
		return []byte(emptyHTML), nil
	}
	s.SetCFClearance("abc123")

	if err := s.syncBrowsePage(context.Background(), "https://downloads.khinsider.com/game-soundtracks/browse/A"); err != nil {
		t.Fatalf("syncBrowsePage: %v", err)
	}
	if gotClearance != "abc123" {
		t.Errorf("cfClearance = %q, want abc123", gotClearance)
	}
}
