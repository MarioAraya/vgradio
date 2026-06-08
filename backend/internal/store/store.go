// Package store persists album metadata to SQLite and manages the audio cache layout.
package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
	_ "modernc.org/sqlite"
)

// ErrNotFound is returned when an album does not exist in the store.
var ErrNotFound = errors.New("store: album not found")

const timeFmt = "2006-01-02T15:04:05Z"

// AlbumID returns a stable, deterministic ID for a given source URL.
// Uses the first 8 bytes of SHA-256 (16 hex chars) — collision-safe at this scale.
func AlbumID(sourceURL string) string {
	h := sha256.Sum256([]byte(sourceURL))
	return fmt.Sprintf("%x", h[:8])
}

// Store is the persistence layer for albums and scrape jobs.
type Store struct {
	db *sql.DB
}

// New opens (or creates) a SQLite database at the given file path and runs migrations.
func New(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// NewTestStore creates an in-memory Store for use in tests.
func NewTestStore(t *testing.T) *Store {
	t.Helper()
	s, err := New(":memory:")
	if err != nil {
		t.Fatalf("store.NewTestStore: %v", err)
	}
	t.Cleanup(func() { s.db.Close() })
	return s
}

func (s *Store) migrate() error {
	// Idempotent column additions for existing databases (ignore error if column exists).
	s.db.Exec(`ALTER TABLE albums ADD COLUMN catalog_number TEXT NOT NULL DEFAULT ''`)  //nolint:errcheck
	s.db.Exec(`ALTER TABLE tracks ADD COLUMN local_path TEXT NOT NULL DEFAULT ''`)      //nolint:errcheck

	s.migrateCatalog()

	_, err := s.db.Exec(`
		PRAGMA journal_mode=WAL;
		PRAGMA foreign_keys=ON;

		CREATE TABLE IF NOT EXISTS albums (
			id             TEXT PRIMARY KEY,
			source_url     TEXT NOT NULL UNIQUE,
			title          TEXT NOT NULL,
			alt_title      TEXT NOT NULL DEFAULT '',
			platform       TEXT NOT NULL DEFAULT '',
			year           INTEGER NOT NULL DEFAULT 0,
			developer      TEXT NOT NULL DEFAULT '',
			publisher      TEXT NOT NULL DEFAULT '',
			catalog_number TEXT NOT NULL DEFAULT '',
			album_type     TEXT NOT NULL DEFAULT '',
			description    TEXT NOT NULL DEFAULT '',
			scraped_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
		);

		CREATE TABLE IF NOT EXISTS tracks (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			album_id     TEXT NOT NULL REFERENCES albums(id),
			idx          INTEGER NOT NULL,
			name         TEXT NOT NULL,
			duration_sec INTEGER NOT NULL DEFAULT 0,
			size_bytes   INTEGER NOT NULL DEFAULT 0,
			page_url     TEXT NOT NULL DEFAULT '',
			song_id      TEXT NOT NULL DEFAULT '',
			mp3_url      TEXT NOT NULL DEFAULT '',
			local_path   TEXT NOT NULL DEFAULT ''
		);

		CREATE TABLE IF NOT EXISTS covers (
			id       INTEGER PRIMARY KEY AUTOINCREMENT,
			album_id TEXT NOT NULL REFERENCES albums(id),
			url      TEXT NOT NULL,
			width    INTEGER NOT NULL DEFAULT 0,
			height   INTEGER NOT NULL DEFAULT 0
		);

		CREATE TABLE IF NOT EXISTS comments (
			id        INTEGER PRIMARY KEY AUTOINCREMENT,
			album_id  TEXT NOT NULL REFERENCES albums(id),
			author    TEXT NOT NULL DEFAULT '',
			body      TEXT NOT NULL DEFAULT '',
			posted_at TEXT NOT NULL DEFAULT ''
		);

		CREATE TABLE IF NOT EXISTS scrape_jobs (
			id          TEXT PRIMARY KEY,
			album_id    TEXT NOT NULL REFERENCES albums(id),
			status      TEXT NOT NULL DEFAULT 'pending',
			error       TEXT NOT NULL DEFAULT '',
			started_at  TEXT,
			finished_at TEXT
		);
	`)
	return err
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
			INSERT INTO covers (album_id, url, width, height) VALUES (?,?,?,?)`,
			albumID, c.URL, c.Width, c.Height,
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

// TrackAlbumID returns the album_id for the given track.
func (s *Store) TrackAlbumID(ctx context.Context, trackID string) (string, error) {
	var albumID string
	err := s.db.QueryRowContext(ctx, `SELECT album_id FROM tracks WHERE id = ?`, trackID).Scan(&albumID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return albumID, err
}

// SetTrackLocalPath stores the absolute path to the downloaded MP3 for a track.
func (s *Store) SetTrackLocalPath(ctx context.Context, trackID, localPath string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE tracks SET local_path = ? WHERE id = ?`, localPath, trackID)
	return err
}

// AlbumSummary is a lightweight album record for list responses.
type AlbumSummary struct {
	ID         string
	Title      string
	Platform   string
	Year       int
	AlbumType  string
	TrackCount int
	CoverURLs  []string // all cover URLs for this album, in insertion order
}

// Albums returns all cached album summaries including cover URLs.
func (s *Store) Albums(ctx context.Context) ([]AlbumSummary, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT a.id, a.title, a.platform, a.year, a.album_type, COUNT(t.id),
		       (SELECT GROUP_CONCAT(url, '|') FROM covers WHERE album_id = a.id)
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
		if err := rows.Scan(&sum.ID, &sum.Title, &sum.Platform, &sum.Year, &sum.AlbumType, &sum.TrackCount, &coverConcat); err != nil {
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

// Track loads a single track by its DB id.
func (s *Store) Track(ctx context.Context, trackID string) (*scraper.Track, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, idx, name, duration_sec, size_bytes, page_url, song_id, mp3_url
		FROM tracks WHERE id = ?`, trackID)
	var tr scraper.Track
	var dbID int64
	err := row.Scan(&dbID, &tr.Index, &tr.Name, &tr.DurationSec, &tr.SizeBytes,
		&tr.PageURL, &tr.SongID, &tr.MP3URL)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	tr.ID = fmt.Sprintf("%d", dbID)
	return &tr, nil
}

// SetTrackMP3URL caches the resolved direct mp3 URL for a track.
func (s *Store) SetTrackMP3URL(ctx context.Context, trackID, mp3URL string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE tracks SET mp3_url = ? WHERE id = ?`, mp3URL, trackID)
	return err
}

func (s *Store) loadCovers(ctx context.Context, albumID string, a *scraper.Album) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT url, width, height FROM covers WHERE album_id = ?`, albumID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var c scraper.Cover
		if err := rows.Scan(&c.URL, &c.Width, &c.Height); err != nil {
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
