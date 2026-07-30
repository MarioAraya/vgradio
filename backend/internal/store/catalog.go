package store

import (
	"context"
	"strings"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

// migrateCatalog adds the catalog tables. Called from migrate().
func (s *Store) migrateCatalog() {
	s.db.Exec(`
		CREATE TABLE IF NOT EXISTS catalog_entries (
			id         TEXT PRIMARY KEY,
			title      TEXT NOT NULL,
			source_url TEXT NOT NULL UNIQUE,
			platform   TEXT NOT NULL DEFAULT '',
			year       INTEGER NOT NULL DEFAULT 0
		);
		CREATE INDEX IF NOT EXISTS idx_catalog_title    ON catalog_entries(title COLLATE NOCASE);
		CREATE INDEX IF NOT EXISTS idx_catalog_platform ON catalog_entries(platform);
		CREATE INDEX IF NOT EXISTS idx_catalog_year     ON catalog_entries(year);`) //nolint:errcheck

	// Add album_type column if not present (idempotent — SQLite errors are ignored).
	s.db.Exec(`ALTER TABLE catalog_entries ADD COLUMN album_type TEXT NOT NULL DEFAULT ''`) //nolint:errcheck

	s.db.Exec(`

		CREATE TABLE IF NOT EXISTS consoles (
			id          TEXT PRIMARY KEY,
			name        TEXT NOT NULL,
			url         TEXT NOT NULL,
			album_count INTEGER NOT NULL DEFAULT 0
		);
	`) //nolint:errcheck

	s.db.Exec(`
		CREATE TABLE IF NOT EXISTS synced_letters (
			letter     TEXT PRIMARY KEY,
			synced_at  TIMESTAMP NOT NULL,
			entries    INTEGER NOT NULL DEFAULT 0
		);
	`) //nolint:errcheck
}

// MarkLetterSynced records that a browse letter has been fully scraped.
func (s *Store) MarkLetterSynced(ctx context.Context, letter string, entries int) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO synced_letters (letter, synced_at, entries)
		VALUES (?, CURRENT_TIMESTAMP, ?)
		ON CONFLICT(letter) DO UPDATE SET
			synced_at = CURRENT_TIMESTAMP,
			entries   = excluded.entries
	`, letter, entries)
	return err
}

// SyncedLetter describes a browse letter's scrape state.
type SyncedLetter struct {
	Letter   string `json:"letter"`
	SyncedAt string `json:"syncedAt"`
	Entries  int    `json:"entries"`
}

// browseLetters is the full set of browse-page suffixes (mirrors catalog.browseLetters).
var browseLetters = func() []string {
	letters := []string{"0-9"}
	for c := 'A'; c <= 'Z'; c++ {
		letters = append(letters, string(c))
	}
	return letters
}()

// SyncedLetters returns every browse letter that already has albums stored in
// catalog_entries — i.e. it does not need to be scraped again to be browsed.
// Counts come straight from catalog_entries (the source of truth), so data
// loaded by any past sync — even before synced_letters existed — counts.
func (s *Store) SyncedLetters(ctx context.Context) ([]SyncedLetter, error) {
	syncedAt := map[string]string{}
	rows, err := s.db.QueryContext(ctx, `SELECT letter, synced_at FROM synced_letters`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var letter, at string
		if err := rows.Scan(&letter, &at); err != nil {
			rows.Close()
			return nil, err
		}
		syncedAt[letter] = at
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	var out []SyncedLetter
	for _, letter := range browseLetters {
		n, err := s.CountCatalog(ctx, "", "", letter)
		if err != nil {
			return nil, err
		}
		if n == 0 {
			continue
		}
		out = append(out, SyncedLetter{Letter: letter, SyncedAt: syncedAt[letter], Entries: n})
	}
	return out, nil
}

// UpsertCatalogEntries inserts or updates catalog entries in bulk.
func (s *Store) UpsertCatalogEntries(ctx context.Context, entries []scraper.CatalogEntry) error {
	if len(entries) == 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO catalog_entries (id, title, source_url, platform, album_type, year)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			title      = excluded.title,
			platform   = excluded.platform,
			album_type = excluded.album_type,
			year       = excluded.year
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, e := range entries {
		id := AlbumID(e.SourceURL)
		if _, err := stmt.ExecContext(ctx, id, e.Title, e.SourceURL, e.Platform, e.AlbumType, e.Year); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// UpsertConsoles inserts or updates console records.
func (s *Store) UpsertConsoles(ctx context.Context, consoles []scraper.Console) error {
	if len(consoles) == 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO consoles (id, name, url, album_count)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name        = excluded.name,
			album_count = excluded.album_count
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, c := range consoles {
		if _, err := stmt.ExecContext(ctx, c.Slug, c.Name, c.URL, c.AlbumCount); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// SearchCatalog returns catalog entries matching the query.
// q: free-text title search; platform: exact match; letter: first letter (or "0-9").
func (s *Store) SearchCatalog(ctx context.Context, q, platform, letter string, offset, limit int) ([]scraper.CatalogEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	where, args := []string{"1=1"}, []any{}

	for _, word := range strings.Fields(q) {
		where = append(where, "title LIKE ?")
		args = append(args, "%"+word+"%")
	}
	if platform != "" {
		where = append(where, "platform LIKE ?")
		args = append(args, "%"+platform+"%")
	}
	if letter != "" {
		if letter == "0-9" {
			where = append(where, "title GLOB '[0-9]*'")
		} else {
			where = append(where, "title LIKE ?")
			args = append(args, strings.ToUpper(letter[:1])+"%")
		}
	}

	args = append(args, limit, offset)
	rows, err := s.db.QueryContext(ctx,
		`SELECT title, source_url, platform, album_type, year FROM catalog_entries
		 WHERE `+strings.Join(where, " AND ")+`
		 ORDER BY title COLLATE NOCASE
		 LIMIT ? OFFSET ?`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []scraper.CatalogEntry
	for rows.Next() {
		var e scraper.CatalogEntry
		if err := rows.Scan(&e.Title, &e.SourceURL, &e.Platform, &e.AlbumType, &e.Year); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// CountCatalog returns the total count matching the same filters as SearchCatalog.
func (s *Store) CountCatalog(ctx context.Context, q, platform, letter string) (int, error) {
	where, args := []string{"1=1"}, []any{}
	for _, word := range strings.Fields(q) {
		where = append(where, "title LIKE ?")
		args = append(args, "%"+word+"%")
	}
	if platform != "" {
		where = append(where, "platform LIKE ?")
		args = append(args, "%"+platform+"%")
	}
	if letter != "" {
		if letter == "0-9" {
			where = append(where, "title GLOB '[0-9]*'")
		} else {
			where = append(where, "title LIKE ?")
			args = append(args, strings.ToUpper(letter[:1])+"%")
		}
	}
	var n int
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM catalog_entries WHERE `+strings.Join(where, " AND "),
		args...,
	).Scan(&n)
	return n, err
}

// Consoles returns all stored consoles with live counts from catalog_entries.
func (s *Store) Consoles(ctx context.Context) ([]scraper.Console, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT c.id, c.name, c.url,
		  (SELECT COUNT(*) FROM catalog_entries e WHERE e.platform LIKE '%' || c.name || '%') AS cnt
		FROM consoles c
		ORDER BY cnt DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []scraper.Console
	for rows.Next() {
		var c scraper.Console
		if err := rows.Scan(&c.Slug, &c.Name, &c.URL, &c.AlbumCount); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
