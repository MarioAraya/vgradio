package store_test

import (
	"context"
	"testing"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

func TestRecentHistory_AnonymousReturnsEmpty(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)

	entries, err := s.RecentHistory(ctx, 10, "")
	if err != nil {
		t.Fatalf("RecentHistory: %v", err)
	}
	if len(entries) != 0 {
		t.Errorf("entries = %v, want empty for anonymous user", entries)
	}
}

func TestRecordPlay_ThenRecentHistory(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, err := s.SaveAlbum(ctx, sampleAlbum())
	if err != nil {
		t.Fatalf("SaveAlbum: %v", err)
	}
	album, err := s.Album(ctx, albumID)
	if err != nil {
		t.Fatalf("Album: %v", err)
	}
	trackID := album.Tracks[0].ID

	if err := s.RecordPlay(ctx, trackID, albumID, "user1"); err != nil {
		t.Fatalf("RecordPlay: %v", err)
	}

	entries, err := s.RecentHistory(ctx, 10, "user1")
	if err != nil {
		t.Fatalf("RecentHistory: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}
	if entries[0].TrackID != trackID {
		t.Errorf("TrackID = %q, want %q", entries[0].TrackID, trackID)
	}
	if entries[0].AlbumTitle != album.Title {
		t.Errorf("AlbumTitle = %q, want %q", entries[0].AlbumTitle, album.Title)
	}

	// A different user must not see this play.
	otherEntries, err := s.RecentHistory(ctx, 10, "user2")
	if err != nil {
		t.Fatalf("RecentHistory (other user): %v", err)
	}
	if len(otherEntries) != 0 {
		t.Errorf("user2 entries = %v, want empty", otherEntries)
	}
}

func TestRecordPlay_SkipsConsecutiveDuplicate(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)
	trackID := album.Tracks[0].ID

	if err := s.RecordPlay(ctx, trackID, albumID, "user1"); err != nil {
		t.Fatalf("RecordPlay 1: %v", err)
	}
	if err := s.RecordPlay(ctx, trackID, albumID, "user1"); err != nil {
		t.Fatalf("RecordPlay 2: %v", err)
	}

	entries, err := s.RecentHistory(ctx, 10, "user1")
	if err != nil {
		t.Fatalf("RecentHistory: %v", err)
	}
	if len(entries) != 1 {
		t.Errorf("len(entries) = %d, want 1 (consecutive duplicate must be skipped)", len(entries))
	}
}
