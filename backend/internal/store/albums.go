package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

// AlbumSummary is a lightweight album record for list responses.
type AlbumSummary struct {
	ID               string
	Title            string
	Platform         string
	Year             int
	AlbumType        string
	TrackCount       int
	TotalDurationSec int
	CoverThumbURL    string   // small preview image of the first cover, for list/search UI
	CoverURLs        []string // all cover URLs for this album, in insertion order
}

// Exists reports whether an album with the given ID is already stored.
func (s *Store) Exists(ctx context.Context, albumID string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM albums WHERE id = ?`, albumID).Scan(&n)
	return n > 0, err
}

// SaveAlbum persists an album (idempotent — safe to call multiple times for the same URL).
// Returns the stable albumID derived from the source URL.
func (s *Store) SaveAlbum(ctx context.Context, a *scraper.Album) (string, error) {
	id := AlbumID(a.SourceURL)

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback() //nolint:errcheck

	res, err := tx.ExecContext(ctx, `
		INSERT OR IGNORE INTO albums
			(id, source_url, title, alt_title, platform, year, developer, publisher, catalog_number, album_type, description)
		VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
		id, a.SourceURL, a.Title, a.AltTitle, a.Platform, a.Year,
		a.Developer, a.Publisher, a.CatalogNumber, a.AlbumType, a.Description,
	)
	if err != nil {
		return "", fmt.Errorf("insert album: %w", err)
	}

	rows, _ := res.RowsAffected()
	if rows > 0 {
		// New album row: insert children.
		if err := insertChildren(ctx, tx, id, a); err != nil {
			return "", err
		}
	}
	// rows == 0 means album already existed — children already present, skip.

	return id, tx.Commit()
}

func insertChildren(ctx context.Context, tx *sql.Tx, albumID string, a *scraper.Album) error {
	for _, tr := range a.Tracks {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO tracks (album_id, idx, name, duration_sec, size_bytes, page_url, song_id, mp3_url)
			VALUES (?,?,?,?,?,?,?,?)`,
			albumID, tr.Index, tr.Name, tr.DurationSec, tr.SizeBytes, tr.PageURL, tr.SongID, tr.MP3URL,
		)
		if err != nil {
			return fmt.Errorf("insert track %d: %w", tr.Index, err)
		}
	}
	for _, c := range a.Covers {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO covers (album_id, url, width, height, thumb_url) VALUES (?,?,?,?,?)`,
			albumID, c.URL, c.Width, c.Height, c.ThumbURL,
		)
		if err != nil {
			return fmt.Errorf("insert cover: %w", err)
		}
	}
	for _, cm := range a.Comments {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO comments (album_id, author, body, posted_at) VALUES (?,?,?,?)`,
			albumID, cm.Author, cm.Body, cm.PostedAt.UTC().Format(timeFmt),
		)
		if err != nil {
			return fmt.Errorf("insert comment: %w", err)
		}
	}
	return nil
}

// Album loads a full album by its ID. Returns ErrNotFound if absent.
func (s *Store) Album(ctx context.Context, albumID string) (*scraper.Album, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT source_url, title, alt_title, platform, year, developer, publisher, catalog_number, album_type, description
		FROM albums WHERE id = ?`, albumID)

	a := &scraper.Album{}
	err := row.Scan(&a.SourceURL, &a.Title, &a.AltTitle, &a.Platform, &a.Year,
		&a.Developer, &a.Publisher, &a.CatalogNumber, &a.AlbumType, &a.Description)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}

	if err := s.loadTracks(ctx, albumID, a); err != nil {
		return nil, err
	}
	if err := s.loadCovers(ctx, albumID, a); err != nil {
		return nil, err
	}
	if err := s.loadComments(ctx, albumID, a); err != nil {
		return nil, err
	}
	return a, nil
}

// DeleteAlbum removes an album and all its rows (tracks, covers, comments,
// scrape jobs, play history). Favorites and playlist entries referencing it
// cascade automatically via FK constraints. Returns ErrNotFound if absent.
// Caller is responsible for removing the album's files on disk.
func (s *Store) DeleteAlbum(ctx context.Context, albumID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	for _, table := range []string{"tracks", "covers", "comments", "scrape_jobs", "play_history"} {
		if _, err := tx.ExecContext(ctx, fmt.Sprintf(`DELETE FROM %s WHERE album_id = ?`, table), albumID); err != nil {
			return err
		}
	}

	res, err := tx.ExecContext(ctx, `DELETE FROM albums WHERE id = ?`, albumID)
	if err != nil {
		return err
	}
	if n, err := res.RowsAffected(); err != nil {
		return err
	} else if n == 0 {
		return ErrNotFound
	}

	return tx.Commit()
}

func (s *Store) loadTracks(ctx context.Context, albumID string, a *scraper.Album) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, idx, name, duration_sec, size_bytes, page_url, song_id, mp3_url, local_path
		FROM tracks WHERE album_id = ? ORDER BY idx`, albumID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var tr scraper.Track
		var dbID int64
		if err := rows.Scan(&dbID, &tr.Index, &tr.Name, &tr.DurationSec, &tr.SizeBytes,
			&tr.PageURL, &tr.SongID, &tr.MP3URL, &tr.LocalPath); err != nil {
			return err
		}
		tr.ID = fmt.Sprintf("%d", dbID)
		a.Tracks = append(a.Tracks, tr)
	}
	return rows.Err()
}

func (s *Store) loadCovers(ctx context.Context, albumID string, a *scraper.Album) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT url, width, height, thumb_url FROM covers WHERE album_id = ?`, albumID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var c scraper.Cover
		if err := rows.Scan(&c.URL, &c.Width, &c.Height, &c.ThumbURL); err != nil {
			return err
		}
		a.Covers = append(a.Covers, c)
	}
	return rows.Err()
}

func (s *Store) loadComments(ctx context.Context, albumID string, a *scraper.Album) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT author, body, posted_at FROM comments WHERE album_id = ? ORDER BY rowid`, albumID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cm scraper.Comment
		var postedAt string
		if err := rows.Scan(&cm.Author, &cm.Body, &postedAt); err != nil {
			return err
		}
		cm.PostedAt, _ = time.Parse(timeFmt, postedAt)
		a.Comments = append(a.Comments, cm)
	}
	return rows.Err()
}

// Albums returns all cached album summaries including cover URLs.
func (s *Store) Albums(ctx context.Context) ([]AlbumSummary, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT a.id, a.title, a.platform, a.year, a.album_type, COUNT(t.id),
		       COALESCE(SUM(t.duration_sec), 0),
		       (SELECT GROUP_CONCAT(url, '|') FROM covers WHERE album_id = a.id),
		       COALESCE((SELECT thumb_url FROM covers WHERE album_id = a.id AND thumb_url != '' ORDER BY id LIMIT 1), '')
		FROM albums a LEFT JOIN tracks t ON t.album_id = a.id
		GROUP BY a.id ORDER BY a.title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AlbumSummary
	for rows.Next() {
		var sum AlbumSummary
		var coverConcat sql.NullString
		if err := rows.Scan(&sum.ID, &sum.Title, &sum.Platform, &sum.Year, &sum.AlbumType, &sum.TrackCount, &sum.TotalDurationSec, &coverConcat, &sum.CoverThumbURL); err != nil {
			return nil, err
		}
		if coverConcat.Valid && coverConcat.String != "" {
			for _, u := range strings.Split(coverConcat.String, "|") {
				if u != "" {
					sum.CoverURLs = append(sum.CoverURLs, u)
				}
			}
		}
		out = append(out, sum)
	}
	return out, rows.Err()
}
