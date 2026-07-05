package store_test

import (
	"context"
	"testing"

	"github.com/arayama/vgradio-app/backend/internal/store"
)

func TestAlbums_EmptyStore(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albums, err := s.Albums(ctx)
	if err != nil {
		t.Fatalf("Albums: %v", err)
	}
	if len(albums) != 0 {
		t.Errorf("albums = %v, want empty", albums)
	}
}

func TestAlbums_SummaryFields(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	in := sampleAlbum()
	albumID, err := s.SaveAlbum(ctx, in)
	if err != nil {
		t.Fatalf("SaveAlbum: %v", err)
	}

	albums, err := s.Albums(ctx)
	if err != nil {
		t.Fatalf("Albums: %v", err)
	}
	if len(albums) != 1 {
		t.Fatalf("len(albums) = %d, want 1", len(albums))
	}
	got := albums[0]
	if got.ID != albumID {
		t.Errorf("ID = %q, want %q", got.ID, albumID)
	}
	if got.TrackCount != len(in.Tracks) {
		t.Errorf("TrackCount = %d, want %d", got.TrackCount, len(in.Tracks))
	}
	wantDuration := 0
	for _, tr := range in.Tracks {
		wantDuration += tr.DurationSec
	}
	if got.TotalDurationSec != wantDuration {
		t.Errorf("TotalDurationSec = %d, want %d", got.TotalDurationSec, wantDuration)
	}
	if len(got.CoverURLs) != 1 || got.CoverURLs[0] != in.Covers[0].URL {
		t.Errorf("CoverURLs = %v, want [%q]", got.CoverURLs, in.Covers[0].URL)
	}
}

func TestLibraryStats_Empty(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	st, err := s.LibraryStats(ctx)
	if err != nil {
		t.Fatalf("LibraryStats: %v", err)
	}
	if st.Albums != 0 || st.Tracks != 0 || st.Scraped != 0 || st.Downloaded != 0 || st.Pending != 0 {
		t.Errorf("stats = %+v, want all zero", st)
	}
}

func TestLibraryStats_WithData(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	albumID, _ := s.SaveAlbum(ctx, sampleAlbum())
	album, _ := s.Album(ctx, albumID)

	if err := s.SetTrackMP3URL(ctx, album.Tracks[0].ID, "https://cdn.example.com/t.mp3"); err != nil {
		t.Fatalf("SetTrackMP3URL: %v", err)
	}

	st, err := s.LibraryStats(ctx)
	if err != nil {
		t.Fatalf("LibraryStats: %v", err)
	}
	if st.Albums != 1 {
		t.Errorf("Albums = %d, want 1", st.Albums)
	}
	if st.Tracks != len(album.Tracks) {
		t.Errorf("Tracks = %d, want %d", st.Tracks, len(album.Tracks))
	}
	if st.Scraped != 1 {
		t.Errorf("Scraped = %d, want 1", st.Scraped)
	}
	if st.Pending != len(album.Tracks)-1 {
		t.Errorf("Pending = %d, want %d", st.Pending, len(album.Tracks)-1)
	}
}
