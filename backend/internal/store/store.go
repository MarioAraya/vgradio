// Package store persists album metadata to SQLite and manages the audio cache layout.
package store

import (
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"testing"

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
	s.db.Exec(`ALTER TABLE albums ADD COLUMN catalog_number TEXT NOT NULL DEFAULT ''`) //nolint:errcheck
	s.db.Exec(`ALTER TABLE tracks ADD COLUMN local_path TEXT NOT NULL DEFAULT ''`)     //nolint:errcheck
	s.db.Exec(`ALTER TABLE play_history ADD COLUMN user_id TEXT`)                      //nolint:errcheck
	s.db.Exec(`ALTER TABLE covers ADD COLUMN thumb_url TEXT NOT NULL DEFAULT ''`)      //nolint:errcheck

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
			id        INTEGER PRIMARY KEY AUTOINCREMENT,
			album_id  TEXT NOT NULL REFERENCES albums(id),
			url       TEXT NOT NULL,
			width     INTEGER NOT NULL DEFAULT 0,
			height    INTEGER NOT NULL DEFAULT 0,
			thumb_url TEXT NOT NULL DEFAULT ''
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

		CREATE TABLE IF NOT EXISTS play_history (
			id        INTEGER PRIMARY KEY AUTOINCREMENT,
			track_id  TEXT NOT NULL,
			album_id  TEXT NOT NULL,
			user_id   TEXT,
			played_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
		);
		CREATE INDEX IF NOT EXISTS idx_play_history_played_at ON play_history(id DESC);

		CREATE TABLE IF NOT EXISTS users (
			id            TEXT PRIMARY KEY,
			username      TEXT NOT NULL UNIQUE,
			email         TEXT NOT NULL UNIQUE,
			password_hash TEXT NOT NULL,
			created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
		);

		CREATE TABLE IF NOT EXISTS sessions (
			id         TEXT PRIMARY KEY,
			user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			expires_at TEXT NOT NULL
		);
		CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

		-- Last playback state per user, so VGRadio Connect can resume after a
		-- backend restart. Devices themselves are never persisted.
		CREATE TABLE IF NOT EXISTS playback_state (
			user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			state_json TEXT NOT NULL,
			updated_at TEXT NOT NULL
		);

		CREATE TABLE IF NOT EXISTS favorites (
			user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			album_id   TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
			PRIMARY KEY (user_id, album_id)
		);

		CREATE TABLE IF NOT EXISTS track_favorites (
			user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			track_id   TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
			created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
			PRIMARY KEY (user_id, track_id)
		);

		CREATE TABLE IF NOT EXISTS playlists (
			id          TEXT PRIMARY KEY,
			user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			name        TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			is_public   INTEGER NOT NULL DEFAULT 0,
			created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
			updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
		);
		CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id);

		CREATE TABLE IF NOT EXISTS playlist_tracks (
			playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
			track_id    TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
			position    INTEGER NOT NULL DEFAULT 0,
			added_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
			PRIMARY KEY (playlist_id, track_id)
		);
		CREATE INDEX IF NOT EXISTS idx_playlist_tracks_list ON playlist_tracks(playlist_id, position);
	`)
	return err
}
