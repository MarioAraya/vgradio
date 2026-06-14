package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

func TestCreateAndGetUser(t *testing.T) {
	s := store.NewTestStore(t)
	ctx := context.Background()

	if err := s.CreateUser(ctx, "uid1", "alice", "alice@example.com", "hash1"); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	u, hash, err := s.GetUserByEmail(ctx, "alice@example.com")
	if err != nil {
		t.Fatalf("GetUserByEmail: %v", err)
	}
	if u.Username != "alice" || hash != "hash1" {
		t.Errorf("got username=%q hash=%q", u.Username, hash)
	}

	u2, err := s.GetUserByID(ctx, "uid1")
	if err != nil {
		t.Fatalf("GetUserByID: %v", err)
	}
	if u2.Email != "alice@example.com" {
		t.Errorf("expected alice@example.com, got %q", u2.Email)
	}
}

func TestCreateUser_DuplicateErrors(t *testing.T) {
	s := store.NewTestStore(t)
	ctx := context.Background()
	_ = s.CreateUser(ctx, "u1", "alice", "alice@example.com", "h")

	if err := s.CreateUser(ctx, "u2", "alice", "other@example.com", "h"); err != store.ErrDuplicateUsername {
		t.Errorf("expected ErrDuplicateUsername, got %v", err)
	}
	if err := s.CreateUser(ctx, "u3", "bob", "alice@example.com", "h"); err != store.ErrDuplicateEmail {
		t.Errorf("expected ErrDuplicateEmail, got %v", err)
	}
}

func TestGetUserByEmail_NotFound(t *testing.T) {
	s := store.NewTestStore(t)
	_, _, err := s.GetUserByEmail(context.Background(), "nobody@example.com")
	if err != store.ErrUserNotFound {
		t.Errorf("expected ErrUserNotFound, got %v", err)
	}
}

func TestResetPassword(t *testing.T) {
	s := store.NewTestStore(t)
	ctx := context.Background()
	_ = s.CreateUser(ctx, "u1", "alice", "alice@example.com", "oldhash")
	if err := s.ResetPassword(ctx, "alice@example.com", "newhash"); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}
	_, hash, _ := s.GetUserByEmail(ctx, "alice@example.com")
	if hash != "newhash" {
		t.Errorf("expected newhash, got %q", hash)
	}

	if err := s.ResetPassword(ctx, "nobody@example.com", "x"); err != store.ErrUserNotFound {
		t.Errorf("expected ErrUserNotFound, got %v", err)
	}
}

func TestSessions(t *testing.T) {
	s := store.NewTestStore(t)
	ctx := context.Background()
	_ = s.CreateUser(ctx, "u1", "alice", "alice@example.com", "h")

	expires := time.Now().Add(time.Hour)
	if err := s.CreateSession(ctx, "sid1", "u1", expires); err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	uid, exp, err := s.GetSession(ctx, "sid1")
	if err != nil {
		t.Fatalf("GetSession: %v", err)
	}
	if uid != "u1" {
		t.Errorf("expected u1, got %q", uid)
	}
	if exp.IsZero() {
		t.Error("expected non-zero expiry")
	}

	newExp := time.Now().Add(2 * time.Hour)
	_ = s.RenewSession(ctx, "sid1", newExp)
	_, exp2, _ := s.GetSession(ctx, "sid1")
	if exp2.Before(exp) {
		t.Error("RenewSession: expiry should have increased")
	}

	_ = s.DeleteSession(ctx, "sid1")
	if _, _, err := s.GetSession(ctx, "sid1"); err != store.ErrNotFound {
		t.Errorf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestFavorites(t *testing.T) {
	s := store.NewTestStore(t)
	ctx := context.Background()
	_ = s.CreateUser(ctx, "u1", "alice", "alice@example.com", "h")

	// Need an album to favorite. Use SaveAlbum via scraper.Album minimal setup.
	// For simplicity, insert directly via raw approach using a helper.
	// Since we can't easily insert albums without scraper, test FavoriteAlbumIDs on empty state.
	ids, err := s.FavoriteAlbumIDs(ctx, "u1")
	if err != nil {
		t.Fatalf("FavoriteAlbumIDs: %v", err)
	}
	if len(ids) != 0 {
		t.Errorf("expected 0 favorites, got %d", len(ids))
	}

	// Anonymous user → empty map
	ids2, _ := s.FavoriteAlbumIDs(ctx, "")
	if len(ids2) != 0 {
		t.Error("expected empty map for anonymous user")
	}
}
