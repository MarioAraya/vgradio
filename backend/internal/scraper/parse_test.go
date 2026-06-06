package scraper

import (
	"os"
	"strings"
	"testing"
)

// loadFixture reads an HTML fixture saved from the origin site (khinsider).
func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return b
}

func TestParseAlbum_Metadata(t *testing.T) {
	html := loadFixture(t, "album.html")
	const src = "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip"

	got, err := ParseAlbum(html, src)
	if err != nil {
		t.Fatalf("ParseAlbum returned error: %v", err)
	}

	checks := []struct {
		field string
		got   any
		want  any
	}{
		{"SourceURL", got.SourceURL, src},
		{"Title", got.Title, "Kirby: Planet Robobot"},
		{"Platform", got.Platform, "3DS"},
		{"Year", got.Year, 2016},
		{"Developer", got.Developer, "HAL Laboratory"},
		{"Publisher", got.Publisher, "Nintendo"},
		{"AlbumType", got.AlbumType, "Gamerip"},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s = %v, want %v", c.field, c.got, c.want)
		}
	}
}

func TestParseAlbum_Tracks(t *testing.T) {
	html := loadFixture(t, "album.html")
	got, err := ParseAlbum(html, "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip")
	if err != nil {
		t.Fatalf("ParseAlbum returned error: %v", err)
	}

	if len(got.Tracks) == 0 {
		t.Fatal("no tracks parsed")
	}

	first := got.Tracks[0]
	if first.Index != 1 {
		t.Errorf("first track Index = %d, want 1", first.Index)
	}
	if first.Name != "airride steel" {
		t.Errorf("first track Name = %q, want %q", first.Name, "airride steel")
	}
	if first.DurationSec != 235 { // 3:55
		t.Errorf("first track DurationSec = %d, want 235", first.DurationSec)
	}
	if first.SizeBytes <= 0 {
		t.Errorf("first track SizeBytes = %d, want > 0", first.SizeBytes)
	}
	if !strings.Contains(first.PageURL, "/album/kirby-planet-robobot-gamerip/") {
		t.Errorf("first track PageURL = %q, missing album path", first.PageURL)
	}
	if !strings.HasPrefix(first.PageURL, "http") {
		t.Errorf("first track PageURL = %q, not absolute", first.PageURL)
	}
	if first.MP3URL != "" {
		t.Errorf("first track MP3URL = %q, want empty before resolution", first.MP3URL)
	}

	// Indices must be sequential 1..N.
	for i, tr := range got.Tracks {
		if tr.Index != i+1 {
			t.Errorf("track[%d] Index = %d, want %d", i, tr.Index, i+1)
		}
		if tr.Name == "" {
			t.Errorf("track[%d] has empty Name", i)
		}
		if tr.PageURL == "" {
			t.Errorf("track[%d] %q has empty PageURL", i, tr.Name)
		}
	}
}

func TestParseAlbum_Covers(t *testing.T) {
	html := loadFixture(t, "album.html")
	got, err := ParseAlbum(html, "https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip")
	if err != nil {
		t.Fatalf("ParseAlbum returned error: %v", err)
	}
	if len(got.Covers) == 0 {
		t.Fatal("expected at least one cover, got none")
	}
	for i, c := range got.Covers {
		if !strings.HasPrefix(c.URL, "http") {
			t.Errorf("cover[%d] URL = %q, not absolute", i, c.URL)
		}
	}
}

func TestParseSongMP3(t *testing.T) {
	html := loadFixture(t, "song.html")
	url, err := ParseSongMP3(html)
	if err != nil {
		t.Fatalf("ParseSongMP3 returned error: %v", err)
	}
	const want = "https://jetta.vgmtreasurechest.com/soundtracks/kirby-planet-robobot-gamerip/vaixqkaxur/airride%20steel%20.mp3"
	if url != want {
		t.Errorf("ParseSongMP3 = %q, want %q", url, want)
	}
}
