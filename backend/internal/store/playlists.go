package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrPlaylistNotFound      = errors.New("store: playlist not found")
	ErrTrackAlreadyInPlaylist = errors.New("store: track already in playlist")
)

// PlaylistSummary is a playlist without its track list.
type PlaylistSummary struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	Description      string   `json:"description"`
	IsPublic         bool     `json:"isPublic"`
	TrackCount       int      `json:"trackCount"`
	TotalDurationSec int      `json:"totalDurationSec"`
	CoverURLs        []string `json:"coverUrls"`
	OwnerID          string   `json:"ownerId"`
	OwnerName        string   `json:"ownerName"`
	CreatedAt        string   `json:"createdAt"`
}

// PlaylistTrack is a track entry inside a playlist.
type PlaylistTrack struct {
	Position    int    `json:"position"`
	ID          string `json:"id"`
	Name        string `json:"name"`
	AlbumID     string `json:"albumId"`
	AlbumTitle  string `json:"albumTitle"`
	Platform    string `json:"platform"`
	Year        int    `json:"year"`
	DurationSec int    `json:"durationSec"`
	StreamURL   string `json:"streamUrl"`
	CoverURL    string `json:"coverUrl"`
}

// PlaylistDetail is a playlist with its full track list.
type PlaylistDetail struct {
	PlaylistSummary
	UpdatedAt string          `json:"updatedAt"`
	Tracks    []PlaylistTrack `json:"tracks"`
}

// CreatePlaylist inserts a new playlist row and returns its summary.
func (s *Store) CreatePlaylist(ctx context.Context, id, userID, name, description string, isPublic bool) (*PlaylistSummary, error) {
	now := time.Now().UTC().Format(timeFmt)
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO playlists (id, user_id, name, description, is_public, created_at, updated_at)
		 VALUES (?,?,?,?,?,?,?)`,
		id, userID, name, description, boolInt(isPublic), now, now)
	if err != nil {
		return nil, err
	}
	var ownerName string
	s.db.QueryRowContext(ctx, `SELECT username FROM users WHERE id=?`, userID).Scan(&ownerName) //nolint:errcheck
	return &PlaylistSummary{
		ID: id, Name: name, Description: description, IsPublic: isPublic,
		OwnerID: userID, OwnerName: ownerName, CoverURLs: []string{}, CreatedAt: now,
	}, nil
}

// ListPlaylists returns the user's own playlists + public playlists of others.
// Pass empty userID to get only public playlists.
func (s *Store) ListPlaylists(ctx context.Context, userID string) ([]PlaylistSummary, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT p.id, p.name, p.description, p.is_public, p.created_at, p.user_id, u.username,
		       COUNT(pt.track_id), COALESCE(SUM(t.duration_sec), 0)
		FROM playlists p
		JOIN users u ON u.id = p.user_id
		LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
		LEFT JOIN tracks t ON CAST(t.id AS TEXT) = pt.track_id
		WHERE p.user_id = ? OR p.is_public = 1
		GROUP BY p.id
		ORDER BY (p.user_id = ?) DESC, p.created_at DESC`, userID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PlaylistSummary
	for rows.Next() {
		var p PlaylistSummary
		var pub int
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &pub, &p.CreatedAt,
			&p.OwnerID, &p.OwnerName, &p.TrackCount, &p.TotalDurationSec); err != nil {
			return nil, err
		}
		p.IsPublic = pub == 1
		p.CoverURLs = s.playlistCoverURLs(ctx, p.ID)
		out = append(out, p)
	}
	if out == nil {
		out = []PlaylistSummary{}
	}
	return out, rows.Err()
}

// GetPlaylist returns a playlist with its full track list.
func (s *Store) GetPlaylist(ctx context.Context, id string) (*PlaylistDetail, error) {
	var p PlaylistDetail
	var pub int
	err := s.db.QueryRowContext(ctx, `
		SELECT p.id, p.name, p.description, p.is_public, p.created_at, p.updated_at, p.user_id, u.username
		FROM playlists p JOIN users u ON u.id = p.user_id
		WHERE p.id = ?`, id).
		Scan(&p.ID, &p.Name, &p.Description, &pub, &p.CreatedAt, &p.UpdatedAt, &p.OwnerID, &p.OwnerName)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrPlaylistNotFound
	}
	if err != nil {
		return nil, err
	}
	p.IsPublic = pub == 1

	tracks, err := s.playlistTracks(ctx, id)
	if err != nil {
		return nil, err
	}
	p.Tracks = tracks
	p.TrackCount = len(tracks)
	for _, t := range tracks {
		p.TotalDurationSec += t.DurationSec
	}
	p.CoverURLs = s.playlistCoverURLs(ctx, id)
	return &p, nil
}

// UpdatePlaylist updates name, description and visibility of a playlist.
func (s *Store) UpdatePlaylist(ctx context.Context, id, name, description string, isPublic bool) error {
	now := time.Now().UTC().Format(timeFmt)
	res, err := s.db.ExecContext(ctx,
		`UPDATE playlists SET name=?, description=?, is_public=?, updated_at=? WHERE id=?`,
		name, description, boolInt(isPublic), now, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrPlaylistNotFound
	}
	return nil
}

// DeletePlaylist removes a playlist and cascades to playlist_tracks.
func (s *Store) DeletePlaylist(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM playlists WHERE id=?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrPlaylistNotFound
	}
	return nil
}

// PlaylistOwner returns the user_id that owns the playlist.
func (s *Store) PlaylistOwner(ctx context.Context, id string) (string, error) {
	var ownerID string
	err := s.db.QueryRowContext(ctx, `SELECT user_id FROM playlists WHERE id=?`, id).Scan(&ownerID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrPlaylistNotFound
	}
	return ownerID, err
}

// PlaylistIsPublic reports whether the playlist is public.
func (s *Store) PlaylistIsPublic(ctx context.Context, id string) (bool, error) {
	var pub int
	err := s.db.QueryRowContext(ctx, `SELECT is_public FROM playlists WHERE id=?`, id).Scan(&pub)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrPlaylistNotFound
	}
	return pub == 1, err
}

// AddTrackToPlaylist appends a track at the next position.
// Returns ErrTrackAlreadyInPlaylist if the track is already present.
func (s *Store) AddTrackToPlaylist(ctx context.Context, playlistID, trackID string) error {
	var maxPos sql.NullInt64
	s.db.QueryRowContext(ctx, //nolint:errcheck
		`SELECT MAX(position) FROM playlist_tracks WHERE playlist_id=?`, playlistID).Scan(&maxPos)
	pos := 0
	if maxPos.Valid {
		pos = int(maxPos.Int64) + 1
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?,?,?)`,
		playlistID, trackID, pos)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "UNIQUE") || strings.Contains(msg, "PRIMARY KEY") {
			return ErrTrackAlreadyInPlaylist
		}
		return err
	}
	s.db.ExecContext(ctx, `UPDATE playlists SET updated_at=? WHERE id=?`, //nolint:errcheck
		time.Now().UTC().Format(timeFmt), playlistID)
	return nil
}

// RemoveTrackFromPlaylist removes a track from a playlist.
func (s *Store) RemoveTrackFromPlaylist(ctx context.Context, playlistID, trackID string) error {
	res, err := s.db.ExecContext(ctx,
		`DELETE FROM playlist_tracks WHERE playlist_id=? AND track_id=?`, playlistID, trackID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	s.db.ExecContext(ctx, `UPDATE playlists SET updated_at=? WHERE id=?`, //nolint:errcheck
		time.Now().UTC().Format(timeFmt), playlistID)
	return nil
}

// ReorderItem is a single {trackID, position} pair for reordering.
type ReorderItem struct {
	TrackID  string `json:"trackId"`
	Position int    `json:"position"`
}

// ReorderPlaylistTracks updates positions for all specified tracks in one transaction.
func (s *Store) ReorderPlaylistTracks(ctx context.Context, playlistID string, items []ReorderItem) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	for _, item := range items {
		if _, err := tx.ExecContext(ctx,
			`UPDATE playlist_tracks SET position=? WHERE playlist_id=? AND track_id=?`,
			item.Position, playlistID, item.TrackID); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE playlists SET updated_at=? WHERE id=?`,
		time.Now().UTC().Format(timeFmt), playlistID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) playlistTracks(ctx context.Context, playlistID string) ([]PlaylistTrack, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT pt.position, CAST(t.id AS TEXT), t.name, t.album_id, a.title, a.platform, a.year,
		       t.duration_sec,
		       COALESCE((SELECT url FROM covers WHERE album_id = t.album_id ORDER BY id LIMIT 1), '')
		FROM playlist_tracks pt
		JOIN tracks t ON CAST(t.id AS TEXT) = pt.track_id
		JOIN albums a ON a.id = t.album_id
		WHERE pt.playlist_id = ?
		ORDER BY pt.position ASC`, playlistID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PlaylistTrack
	for rows.Next() {
		var tr PlaylistTrack
		if err := rows.Scan(&tr.Position, &tr.ID, &tr.Name, &tr.AlbumID, &tr.AlbumTitle,
			&tr.Platform, &tr.Year, &tr.DurationSec, &tr.CoverURL); err != nil {
			return nil, err
		}
		tr.StreamURL = fmt.Sprintf("/tracks/%s/stream", tr.ID)
		out = append(out, tr)
	}
	if out == nil {
		out = []PlaylistTrack{}
	}
	return out, rows.Err()
}

func (s *Store) playlistCoverURLs(ctx context.Context, playlistID string) []string {
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT COALESCE((SELECT url FROM covers WHERE album_id = t.album_id ORDER BY id LIMIT 1), '')
		FROM playlist_tracks pt
		JOIN tracks t ON CAST(t.id AS TEXT) = pt.track_id
		WHERE pt.playlist_id = ?
		LIMIT 4`, playlistID)
	if err != nil {
		return []string{}
	}
	defer rows.Close()
	var urls []string
	for rows.Next() {
		var u string
		if rows.Scan(&u) == nil && u != "" {
			urls = append(urls, u)
		}
	}
	if urls == nil {
		return []string{}
	}
	return urls
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
