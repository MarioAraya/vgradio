package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/connect"
)

// SavePlaybackState upserts the user's playback state. Callers are expected to
// debounce: the hub writes at most once per sweep plus once on pause, because a
// playing client publishes several times a minute.
func (s *Store) SavePlaybackState(ctx context.Context, userID string, state connect.PlaybackState) error {
	blob, err := json.Marshal(state)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO playback_state (user_id, state_json, updated_at)
		VALUES (?, ?, ?)
		ON CONFLICT(user_id) DO UPDATE SET state_json = excluded.state_json,
		                                   updated_at = excluded.updated_at`,
		userID, string(blob), time.Now().UTC().Format(timeFmt))
	return err
}

// LoadPlaybackState returns the stored state, or found=false when the user has
// none yet.
func (s *Store) LoadPlaybackState(ctx context.Context, userID string) (connect.PlaybackState, bool, error) {
	var blob string
	err := s.db.QueryRowContext(ctx,
		`SELECT state_json FROM playback_state WHERE user_id = ?`, userID).Scan(&blob)
	if errors.Is(err, sql.ErrNoRows) {
		return connect.PlaybackState{}, false, nil
	}
	if err != nil {
		return connect.PlaybackState{}, false, err
	}
	var state connect.PlaybackState
	if err := json.Unmarshal([]byte(blob), &state); err != nil {
		// A row we cannot parse is worse than no row: treat it as absent so the
		// user gets an empty player instead of an error on every connect.
		return connect.PlaybackState{}, false, nil
	}
	return state, true, nil
}
