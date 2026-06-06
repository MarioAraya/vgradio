// Package scraper turns origin-site HTML into domain structs.
// It is pure: HTML bytes in, structs out. No network, no disk — fully testable.
package scraper

import "time"

// Album is a scraped music album with its metadata, covers, tracks and comments.
type Album struct {
	SourceURL     string
	Title         string
	AltTitle      string // newline-separated alternate titles (Japanese, romanized, etc.)
	Platform      string // comma-separated: "PS3, PS4, Switch, Windows, Xbox One"
	Year          int
	Developer     string
	Publisher     string // comma-separated when multiple
	CatalogNumber string // e.g. "LNCM-1175~7"
	AlbumType     string // Gamerip, Soundtrack, ...
	Description   string
	Covers        []Cover
	Tracks        []Track
	Comments      []Comment
}

// Cover is an album artwork image.
type Cover struct {
	URL    string
	Width  int
	Height int
}

// Track is a single song within an album.
//
// The origin site does not expose the direct .mp3 on the album page: each track
// links to a per-song page (PageURL). The direct MP3 is resolved in a second step
// (ParseSongMP3) and stored in MP3URL — empty until resolved.
type Track struct {
	ID          string // DB-assigned identifier (set by store, empty from scraper)
	Index       int
	Name        string
	DurationSec int
	SizeBytes   int64  // MP3 size
	PageURL     string // per-song detail page on the origin site
	SongID      string // origin-site song id (from playlistAddTo)
	MP3URL      string // direct .mp3, resolved lazily via ParseSongMP3
}

// Comment is a user comment from the album page.
type Comment struct {
	Author   string
	Body     string
	PostedAt time.Time
}
