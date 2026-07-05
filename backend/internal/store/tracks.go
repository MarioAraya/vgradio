package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
)

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

// DownloadedAlbum is an album that has at least one locally-downloaded track.
type DownloadedAlbum struct {
	ID         string   `json:"id"`
	Title      string   `json:"title"`
	Platform   string   `json:"platform"`
	Year       int      `json:"year"`
	CoverURL   string   `json:"coverUrl"`
	TrackCount int      `json:"trackCount"`
	Downloaded int      `json:"downloaded"`
	LocalPaths []string `json:"-"`
}

func (s *Store) AlbumsWithDownloads(ctx context.Context) ([]DownloadedAlbum, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT a.id, a.title, a.platform, a.year,
		       COALESCE((SELECT url FROM covers WHERE album_id = a.id ORDER BY id LIMIT 1), ''),
		       COUNT(t.id),
		       SUM(CASE WHEN t.local_path != '' THEN 1 ELSE 0 END),
		       GROUP_CONCAT(CASE WHEN t.local_path != '' THEN t.local_path ELSE NULL END, '|')
		FROM albums a
		JOIN tracks t ON t.album_id = a.id
		GROUP BY a.id
		HAVING SUM(CASE WHEN t.local_path != '' THEN 1 ELSE 0 END) > 0
		ORDER BY a.title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DownloadedAlbum
	for rows.Next() {
		var d DownloadedAlbum
		var pathConcat sql.NullString
		if err := rows.Scan(&d.ID, &d.Title, &d.Platform, &d.Year, &d.CoverURL,
			&d.TrackCount, &d.Downloaded, &pathConcat); err != nil {
			return nil, err
		}
		if pathConcat.Valid && pathConcat.String != "" {
			for _, p := range strings.Split(pathConcat.String, "|") {
				if p != "" {
					d.LocalPaths = append(d.LocalPaths, p)
				}
			}
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// ClearAlbumLocalPaths clears local_path for all tracks of an album and returns the paths
// that were set so the caller can delete the files.
func (s *Store) ClearAlbumLocalPaths(ctx context.Context, albumID string) ([]string, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT local_path FROM tracks WHERE album_id = ? AND local_path != ''`, albumID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var paths []string
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, err
		}
		paths = append(paths, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	_, err = s.db.ExecContext(ctx, `UPDATE tracks SET local_path = '' WHERE album_id = ?`, albumID)
	return paths, err
}

// PendingTrack is a track with a page_url but no mp3_url yet.
type PendingTrack struct {
	ID      string
	PageURL string
}

func (s *Store) PendingTracks(ctx context.Context) ([]PendingTrack, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, page_url FROM tracks WHERE mp3_url = '' AND page_url != ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PendingTrack
	for rows.Next() {
		var t PendingTrack
		if err := rows.Scan(&t.ID, &t.PageURL); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
