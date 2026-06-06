package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/scraper"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

func sampleAlbum() *scraper.Album {
	return &scraper.Album{
		SourceURL:   "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip",
		Title:       "Kirby: Planet Robobot",
		Platform:    "3DS",
		Year:        2016,
		Developer:   "HAL Laboratory",
		Publisher:   "Nintendo",
		AlbumType:   "Gamerip",
		Description: "Great rip.",
		Covers: []scraper.Cover{
			{URL: "https://example.com/cover.jpg", Width: 300, Height: 300},
		},
		Tracks: []scraper.Track{
			{Index: 1, Name: "airride steel", DurationSec: 235, SizeBytes: 6144655, PageURL: "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip/airride%2520steel%2520.mp3", SongID: "4033558"},
			{Index: 2, Name: "Ayasii", DurationSec: 120, SizeBytes: 3000000, PageURL: "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip/Ayasii%2520.mp3", SongID: "4033559"},
		},
		Comments: []scraper.Comment{
			{Author: "user1", Body: "great rip", PostedAt: time.Date(2020, 10, 26, 0, 0, 0, 0, time.UTC)},
		},
	}
}

func TestAlbumID_StableHash(t *testing.T) {
	url := "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip"
	id1 := store.AlbumID(url)
	id2 := store.AlbumID(url)
	if id1 != id2 {
		t.Errorf("AlbumID not stable: %q vs %q", id1, id2)
	}
	if id1 == "" {
		t.Error("AlbumID returned empty string")
	}
	// Different URL must produce different ID.
	other := store.AlbumID("https://downloads.khinsider.com/game-soundtracks/album/persona-5")
	if id1 == other {
		t.Error("different URLs produced same AlbumID")
	}
}

func TestSaveAndLoadAlbum(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)

	in := sampleAlbum()
	albumID, err := s.SaveAlbum(ctx, in)
	if err != nil {
		t.Fatalf("SaveAlbum: %v", err)
	}
	if albumID == "" {
		t.Fatal("SaveAlbum returned empty albumID")
	}

	got, err := s.Album(ctx, albumID)
	if err != nil {
		t.Fatalf("Album: %v", err)
	}

	// Metadata round-trip.
	if got.SourceURL != in.SourceURL {
		t.Errorf("SourceURL = %q, want %q", got.SourceURL, in.SourceURL)
	}
	if got.Title != in.Title {
		t.Errorf("Title = %q, want %q", got.Title, in.Title)
	}
	if got.Platform != in.Platform {
		t.Errorf("Platform = %q, want %q", got.Platform, in.Platform)
	}
	if got.Year != in.Year {
		t.Errorf("Year = %d, want %d", got.Year, in.Year)
	}
	if got.Developer != in.Developer {
		t.Errorf("Developer = %q, want %q", got.Developer, in.Developer)
	}
	if got.AlbumType != in.AlbumType {
		t.Errorf("AlbumType = %q, want %q", got.AlbumType, in.AlbumType)
	}

	// Tracks.
	if len(got.Tracks) != len(in.Tracks) {
		t.Fatalf("len(Tracks) = %d, want %d", len(got.Tracks), len(in.Tracks))
	}
	tr := got.Tracks[0]
	if tr.Name != "airride steel" || tr.DurationSec != 235 || tr.SizeBytes != 6144655 {
		t.Errorf("track[0] = %+v, want airride steel/235/6144655", tr)
	}
	if tr.PageURL == "" {
		t.Error("track[0] PageURL empty after round-trip")
	}
	if tr.SongID != "4033558" {
		t.Errorf("track[0] SongID = %q, want 4033558", tr.SongID)
	}

	// Covers.
	if len(got.Covers) != 1 {
		t.Fatalf("len(Covers) = %d, want 1", len(got.Covers))
	}
	if got.Covers[0].URL != in.Covers[0].URL {
		t.Errorf("cover URL = %q, want %q", got.Covers[0].URL, in.Covers[0].URL)
	}

	// Comments.
	if len(got.Comments) != 1 {
		t.Fatalf("len(Comments) = %d, want 1", len(got.Comments))
	}
	if got.Comments[0].Author != "user1" {
		t.Errorf("comment author = %q, want user1", got.Comments[0].Author)
	}
}

func TestExists(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)

	albumID := store.AlbumID(sampleAlbum().SourceURL)

	exists, err := s.Exists(ctx, albumID)
	if err != nil {
		t.Fatalf("Exists (before save): %v", err)
	}
	if exists {
		t.Error("Exists = true before SaveAlbum")
	}

	if _, err := s.SaveAlbum(ctx, sampleAlbum()); err != nil {
		t.Fatalf("SaveAlbum: %v", err)
	}

	exists, err = s.Exists(ctx, albumID)
	if err != nil {
		t.Fatalf("Exists (after save): %v", err)
	}
	if !exists {
		t.Error("Exists = false after SaveAlbum")
	}
}

func TestSaveAlbum_Idempotent(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)

	in := sampleAlbum()
	id1, err := s.SaveAlbum(ctx, in)
	if err != nil {
		t.Fatalf("first SaveAlbum: %v", err)
	}
	id2, err := s.SaveAlbum(ctx, in)
	if err != nil {
		t.Fatalf("second SaveAlbum: %v", err)
	}
	if id1 != id2 {
		t.Errorf("albumIDs differ across saves: %q vs %q", id1, id2)
	}

	// Must not duplicate tracks.
	got, err := s.Album(ctx, id1)
	if err != nil {
		t.Fatalf("Album after double save: %v", err)
	}
	if len(got.Tracks) != len(in.Tracks) {
		t.Errorf("tracks duplicated: got %d, want %d", len(got.Tracks), len(in.Tracks))
	}
}

func TestAlbum_NotFound(t *testing.T) {
	ctx := context.Background()
	s := store.NewTestStore(t)
	_, err := s.Album(ctx, "nonexistent-id")
	if err == nil {
		t.Error("expected error for nonexistent albumID, got nil")
	}
}
