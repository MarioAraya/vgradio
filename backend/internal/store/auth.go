package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

var (
	ErrUserNotFound      = errors.New("store: user not found")
	ErrDuplicateUsername = errors.New("store: username already in use")
	ErrDuplicateEmail    = errors.New("store: email already in use")
)

// User is an authenticated account.
type User struct {
	ID       string
	Username string
	Email    string
}

const sessionTTL = 30 * 24 * time.Hour

// CreateUser inserts a new user row. Returns ErrDuplicate* on unique constraint violations.
func (s *Store) CreateUser(ctx context.Context, id, username, email, passwordHash string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO users (id, username, email, password_hash) VALUES (?,?,?,?)`,
		id, username, email, passwordHash)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "users.username") {
			return ErrDuplicateUsername
		}
		if strings.Contains(msg, "users.email") {
			return ErrDuplicateEmail
		}
	}
	return err
}

// GetUserByEmail looks up a user and their password hash by email.
// Returns (nil, ErrUserNotFound) when absent.
func (s *Store) GetUserByEmail(ctx context.Context, email string) (*User, string, error) {
	var u User
	var hash string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, username, email, password_hash FROM users WHERE email = ?`, email).
		Scan(&u.ID, &u.Username, &u.Email, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, "", ErrUserNotFound
	}
	return &u, hash, err
}

// GetUserByID looks up a user by ID. Returns (nil, ErrUserNotFound) when absent.
func (s *Store) GetUserByID(ctx context.Context, id string) (*User, error) {
	var u User
	err := s.db.QueryRowContext(ctx,
		`SELECT id, username, email FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Username, &u.Email)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	return &u, err
}

// ResetPassword updates the password hash for the user with the given email.
func (s *Store) ResetPassword(ctx context.Context, email, passwordHash string) error {
	res, err := s.db.ExecContext(ctx,
		`UPDATE users SET password_hash = ? WHERE email = ?`, passwordHash, email)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// CreateSession inserts a new session row.
func (s *Store) CreateSession(ctx context.Context, sessionID, userID string, expiresAt time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions (id, user_id, expires_at) VALUES (?,?,?)`,
		sessionID, userID, expiresAt.UTC().Format(timeFmt))
	return err
}

// GetSession returns the userID and expiry for a session. Returns ErrNotFound when absent.
func (s *Store) GetSession(ctx context.Context, sessionID string) (userID string, expiresAt time.Time, err error) {
	var expiresStr string
	err = s.db.QueryRowContext(ctx,
		`SELECT user_id, expires_at FROM sessions WHERE id = ?`, sessionID).
		Scan(&userID, &expiresStr)
	if errors.Is(err, sql.ErrNoRows) {
		return "", time.Time{}, ErrNotFound
	}
	if err != nil {
		return "", time.Time{}, err
	}
	expiresAt, err = time.Parse(timeFmt, expiresStr)
	return userID, expiresAt, err
}

// RenewSession updates the expiry of an existing session (sliding window).
func (s *Store) RenewSession(ctx context.Context, sessionID string, expiresAt time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE sessions SET expires_at = ? WHERE id = ?`,
		expiresAt.UTC().Format(timeFmt), sessionID)
	return err
}

// DeleteSession removes a session (logout).
func (s *Store) DeleteSession(ctx context.Context, sessionID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE id = ?`, sessionID)
	return err
}

// ToggleFavorite adds or removes an album from a user's favorites.
// Returns true if the album is now favorited, false if it was removed.
func (s *Store) ToggleFavorite(ctx context.Context, userID, albumID string) (bool, error) {
	var count int
	s.db.QueryRowContext(ctx, //nolint:errcheck
		`SELECT COUNT(*) FROM favorites WHERE user_id = ? AND album_id = ?`, userID, albumID).Scan(&count)
	if count > 0 {
		_, err := s.db.ExecContext(ctx,
			`DELETE FROM favorites WHERE user_id = ? AND album_id = ?`, userID, albumID)
		return false, err
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO favorites (user_id, album_id) VALUES (?,?)`, userID, albumID)
	return err == nil, err
}

// GetFavorites returns album summaries for all albums favorited by userID, newest first.
func (s *Store) GetFavorites(ctx context.Context, userID string) ([]AlbumSummary, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT a.id, a.title, a.platform, a.year, a.album_type, COUNT(t.id),
		       (SELECT GROUP_CONCAT(url, '|') FROM covers WHERE album_id = a.id)
		FROM favorites f
		JOIN albums a ON a.id = f.album_id
		LEFT JOIN tracks t ON t.album_id = a.id
		WHERE f.user_id = ?
		GROUP BY a.id
		ORDER BY f.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AlbumSummary
	for rows.Next() {
		var sum AlbumSummary
		var coverConcat sql.NullString
		if err := rows.Scan(&sum.ID, &sum.Title, &sum.Platform, &sum.Year,
			&sum.AlbumType, &sum.TrackCount, &coverConcat); err != nil {
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
	if out == nil {
		out = []AlbumSummary{}
	}
	return out, rows.Err()
}

// FavoriteAlbumIDs returns a set of album IDs that userID has favorited.
// Returns an empty map for empty userID.
func (s *Store) FavoriteAlbumIDs(ctx context.Context, userID string) (map[string]bool, error) {
	out := map[string]bool{}
	if userID == "" {
		return out, nil
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT album_id FROM favorites WHERE user_id = ?`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}
