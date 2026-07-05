package store

import "context"

// HistoryEntry is a single recently-played record enriched with track/album metadata.
type HistoryEntry struct {
	TrackID    string `json:"trackId"`
	TrackName  string `json:"trackName"`
	AlbumID    string `json:"albumId"`
	AlbumTitle string `json:"albumTitle"`
	Platform   string `json:"platform"`
	Year       int    `json:"year"`
	CoverURL   string `json:"coverUrl"`
	PlayedAt   string `json:"playedAt"`
}

// RecordPlay inserts a play_history row. Skips if the same track_id is the most recent entry.
// userID may be empty for anonymous plays.
func (s *Store) RecordPlay(ctx context.Context, trackID, albumID, userID string) error {
	var lastTrackID string
	s.db.QueryRowContext(ctx, `SELECT track_id FROM play_history ORDER BY id DESC LIMIT 1`).Scan(&lastTrackID) //nolint:errcheck
	if lastTrackID == trackID {
		return nil
	}
	var uid any
	if userID != "" {
		uid = userID
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO play_history (track_id, album_id, user_id) VALUES (?, ?, ?)`, trackID, albumID, uid)
	return err
}

// RecentHistory returns the last N play_history entries for userID enriched with track/album metadata.
// Rows whose track or album was deleted are omitted. Returns empty slice for empty userID.
func (s *Store) RecentHistory(ctx context.Context, limit int, userID string) ([]HistoryEntry, error) {
	if userID == "" {
		return []HistoryEntry{}, nil
	}
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT ph.track_id, t.name, ph.album_id, a.title, a.platform, a.year,
		       COALESCE((SELECT url FROM covers WHERE album_id = ph.album_id ORDER BY id LIMIT 1), ''),
		       ph.played_at
		FROM play_history ph
		JOIN tracks t  ON CAST(t.id AS TEXT) = ph.track_id
		JOIN albums a  ON a.id = ph.album_id
		WHERE ph.user_id = ?
		ORDER BY ph.id DESC
		LIMIT ?`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []HistoryEntry
	for rows.Next() {
		var e HistoryEntry
		if err := rows.Scan(&e.TrackID, &e.TrackName, &e.AlbumID, &e.AlbumTitle,
			&e.Platform, &e.Year, &e.CoverURL, &e.PlayedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if out == nil {
		out = []HistoryEntry{}
	}
	return out, rows.Err()
}
