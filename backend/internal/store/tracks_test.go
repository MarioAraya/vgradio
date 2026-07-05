package store_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

func TestTrackAlbumID(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)
	trackID := album.Tracks[0].ID

	got, err := s.TrackAlbumID(ctx, trackID)
	if err != nil {
		t.Fatalf("TrackAlbumID: %v", err)
	}
	if got != albumID {
		t.Errorf("albumID = %q, want %q", got, albumID)
	}
}

func TestTrackAlbumID_NotFound(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	_, err := s.TrackAlbumID(ctx, "9999")
	if err != store.ErrNotFound {
		t.Errorf("err = %v, want ErrNotFound", err)
	}
}

func TestTrack_NotFound(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	_, err := s.Track(ctx, "9999")
	if err != store.ErrNotFound {
		t.Errorf("err = %v, want ErrNotFound", err)
	}
}

func TestSetTrackMP3URL_AndLocalPath(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)
	trackID := album.Tracks[0].ID

	if err := s.SetTrackMP3URL(ctx, trackID, "https://cdn.example.com/t.mp3"); err != nil {
		t.Fatalf("SetTrackMP3URL: %v", err)
	}
	if err := s.SetTrackLocalPath(ctx, trackID, "/tmp/t.mp3"); err != nil {
		t.Fatalf("SetTrackLocalPath: %v", err)
	}

	tr, err := s.Track(ctx, trackID)
	if err != nil {
		t.Fatalf("Track: %v", err)
	}
	if tr.MP3URL != "https://cdn.example.com/t.mp3" {
		t.Errorf("MP3URL = %q, want cdn url", tr.MP3URL)
	}
}

func TestPendingTracks(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)

	pending, err := s.PendingTracks(ctx)
	if err != nil {
		t.Fatalf("PendingTracks: %v", err)
	}
	if len(pending) != len(album.Tracks) {
		t.Fatalf("len(pending) = %d, want %d (all tracks have page_url, none have mp3_url)", len(pending), len(album.Tracks))
	}

	// Resolving one track's mp3_url should remove it from pending.
	if err := s.SetTrackMP3URL(ctx, album.Tracks[0].ID, "https://cdn.example.com/t.mp3"); err != nil {
		t.Fatalf("SetTrackMP3URL: %v", err)
	}
	pending, err = s.PendingTracks(ctx)
	if err != nil {
		t.Fatalf("PendingTracks (after resolve): %v", err)
	}
	if len(pending) != len(album.Tracks)-1 {
		t.Errorf("len(pending) = %d, want %d", len(pending), len(album.Tracks)-1)
	}
}

func TestAlbumsWithDownloads(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)

	empty, err := s.AlbumsWithDownloads(ctx)
	if err != nil {
		t.Fatalf("AlbumsWithDownloads (before download): %v", err)
	}
	if len(empty) != 0 {
		t.Errorf("AlbumsWithDownloads = %v, want empty before any download", empty)
	}

	tmpFile := filepath.Join(t.TempDir(), "track.mp3")
	if err := os.WriteFile(tmpFile, []byte("fake"), 0o644); err != nil {
		t.Fatalf("write tmp file: %v", err)
	}
	if err := s.SetTrackLocalPath(ctx, album.Tracks[0].ID, tmpFile); err != nil {
		t.Fatalf("SetTrackLocalPath: %v", err)
	}

	downloaded, err := s.AlbumsWithDownloads(ctx)
	if err != nil {
		t.Fatalf("AlbumsWithDownloads: %v", err)
	}
	if len(downloaded) != 1 {
		t.Fatalf("len(downloaded) = %d, want 1", len(downloaded))
	}
	if downloaded[0].ID != albumID {
		t.Errorf("ID = %q, want %q", downloaded[0].ID, albumID)
	}
	if downloaded[0].Downloaded != 1 {
		t.Errorf("Downloaded = %d, want 1", downloaded[0].Downloaded)
	}
	if len(downloaded[0].LocalPaths) != 1 || downloaded[0].LocalPaths[0] != tmpFile {
		t.Errorf("LocalPaths = %v, want [%q]", downloaded[0].LocalPaths, tmpFile)
	}
}

func TestClearAlbumLocalPaths(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)

	if err := s.SetTrackLocalPath(ctx, album.Tracks[0].ID, "/tmp/a.mp3"); err != nil {
		t.Fatalf("SetTrackLocalPath: %v", err)
	}

	paths, err := s.ClearAlbumLocalPaths(ctx, albumID)
	if err != nil {
		t.Fatalf("ClearAlbumLocalPaths: %v", err)
	}
	if len(paths) != 1 || paths[0] != "/tmp/a.mp3" {
		t.Errorf("paths = %v, want [/tmp/a.mp3]", paths)
	}

	reloaded, err := s.Album(ctx, albumID)
	if err != nil {
		t.Fatalf("Album: %v", err)
	}
	if reloaded.Tracks[0].LocalPath != "" {
		t.Errorf("LocalPath = %q, want empty after clear", reloaded.Tracks[0].LocalPath)
	}
}
