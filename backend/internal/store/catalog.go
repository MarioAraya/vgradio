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
		CREATE INDEX IF NOT EXISTS idx_catalog_year     ON catalog_entries(year);

		CREATE TABLE IF NOT EXISTS consoles (
			id          TEXT PRIMARY KEY,
			name        TEXT NOT NULL,
			url         TEXT NOT NULL,
			album_count INTEGER NOT NULL DEFAULT 0
		);
	`) //nolint:errcheck
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
		INSERT INTO catalog_entries (id, title, source_url, platform, year)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			title    = excluded.title,
			platform = excluded.platform,
			year     = excluded.year
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, e := range entries {
		id := AlbumID(e.SourceURL)
		if _, err := stmt.ExecContext(ctx, id, e.Title, e.SourceURL, e.Platform, e.Year); err != nil {
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

	if q != "" {
		where = append(where, "title LIKE ?")
		args = append(args, "%"+q+"%")
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
		`SELECT title, source_url, platform, year FROM catalog_entries
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
		if err := rows.Scan(&e.Title, &e.SourceURL, &e.Platform, &e.Year); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// CountCatalog returns the total count matching the same filters as SearchCatalog.
func (s *Store) CountCatalog(ctx context.Context, q, platform, letter string) (int, error) {
	where, args := []string{"1=1"}, []any{}
	if q != "" {
		where = append(where, "title LIKE ?")
		args = append(args, "%"+q+"%")
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

// Consoles returns all stored consoles ordered by album_count desc.
func (s *Store) Consoles(ctx context.Context) ([]scraper.Console, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, name, url, album_count FROM consoles ORDER BY album_count DESC`)
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
