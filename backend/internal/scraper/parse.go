package scraper

import (
	"bytes"
	"errors"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// ErrParse is returned when the HTML does not contain the expected structure.
var ErrParse = errors.New("scraper: unexpected HTML structure")

// Metadata is read from the album info block via labelled fields.
var (
	reYear      = regexp.MustCompile(`(?is)Year:\s*<b>(\d+)</b>`)
	rePlatform  = regexp.MustCompile(`(?is)Platforms?:\s*<[ab][^>]*>(.*?)</`)
	reDeveloper = regexp.MustCompile(`(?is)Developed by:\s*<a[^>]*>(.*?)</a>`)
	rePublisher = regexp.MustCompile(`(?is)Published by:\s*<a[^>]*>(.*?)</a>`)
	reAlbumType = regexp.MustCompile(`(?is)Album type:\s*<b>(?:<a[^>]*>)?(.*?)</`)
)

// ParseAlbum parses an album page's HTML into an Album.
// sourceURL is the page URL the HTML came from (used to resolve relative links).
func ParseAlbum(html []byte, sourceURL string) (*Album, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, err := url.Parse(sourceURL)
	if err != nil {
		return nil, err
	}

	a := &Album{SourceURL: sourceURL}
	a.Title = strings.TrimSpace(doc.Find("h2").First().Text())
	if a.Title == "" {
		return nil, ErrParse
	}

	a.Platform = firstSubmatch(rePlatform, html)
	a.Developer = firstSubmatch(reDeveloper, html)
	a.Publisher = firstSubmatch(rePublisher, html)
	a.AlbumType = firstSubmatch(reAlbumType, html)
	if y := firstSubmatch(reYear, html); y != "" {
		a.Year, _ = strconv.Atoi(y)
	}

	a.Covers = parseCovers(doc, base)
	a.Tracks = parseTracks(doc, base)
	return a, nil
}

// ParseSongMP3 parses a per-song page's HTML and returns the direct .mp3 URL.
func ParseSongMP3(html []byte) (string, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return "", err
	}
	if src, ok := doc.Find("audio#audio").Attr("src"); ok && src != "" {
		return strings.TrimSpace(src), nil
	}
	// Fallback: first anchor pointing at an .mp3.
	if href, ok := doc.Find(`a[href$=".mp3"]`).First().Attr("href"); ok && href != "" {
		return strings.TrimSpace(href), nil
	}
	return "", ErrParse
}

func parseCovers(doc *goquery.Document, base *url.URL) []Cover {
	var covers []Cover
	doc.Find("div.albumImage a").Each(func(_ int, s *goquery.Selection) {
		href, ok := s.Attr("href")
		if !ok || href == "" {
			return
		}
		covers = append(covers, Cover{URL: absURL(base, href)})
	})
	return covers
}

func parseTracks(doc *goquery.Document, base *url.URL) []Track {
	var tracks []Track
	idx := 0
	doc.Find("table#songlist tr").Each(func(_ int, row *goquery.Selection) {
		links := row.Find("td.clickable-row a")
		if links.Length() == 0 {
			return // header / non-track row
		}
		name := strings.TrimSpace(links.Eq(0).Text())
		href, _ := links.Eq(0).Attr("href")
		if name == "" || href == "" {
			return
		}
		idx++
		t := Track{
			Index:   idx,
			Name:    name,
			PageURL: absURL(base, href),
			SongID:  strings.TrimSpace(row.Find(".playlistAddTo").AttrOr("songid", "")),
		}
		// Columns after the name: duration, MP3 size, FLAC size.
		if links.Length() > 1 {
			t.DurationSec = parseDuration(links.Eq(1).Text())
		}
		if links.Length() > 2 {
			t.SizeBytes = parseSize(links.Eq(2).Text())
		}
		tracks = append(tracks, t)
	})
	return tracks
}

func firstSubmatch(re *regexp.Regexp, html []byte) string {
	m := re.FindSubmatch(html)
	if len(m) < 2 {
		return ""
	}
	return strings.TrimSpace(string(m[1]))
}

func absURL(base *url.URL, href string) string {
	ref, err := url.Parse(href)
	if err != nil {
		return href
	}
	return base.ResolveReference(ref).String()
}

// parseDuration converts "m:ss" or "h:mm:ss" into seconds.
func parseDuration(s string) int {
	parts := strings.Split(strings.TrimSpace(s), ":")
	secs := 0
	for _, p := range parts {
		n, err := strconv.Atoi(strings.TrimSpace(p))
		if err != nil {
			return 0
		}
		secs = secs*60 + n
	}
	return secs
}

// parseSize converts "5.86 MB" / "920 KB" / "1.2 GB" into bytes.
func parseSize(s string) int64 {
	f := strings.Fields(strings.TrimSpace(s))
	if len(f) != 2 {
		return 0
	}
	val, err := strconv.ParseFloat(f[0], 64)
	if err != nil {
		return 0
	}
	var mult float64
	switch strings.ToUpper(f[1]) {
	case "B":
		mult = 1
	case "KB":
		mult = 1 << 10
	case "MB":
		mult = 1 << 20
	case "GB":
		mult = 1 << 30
	default:
		return 0
	}
	return int64(val * mult)
}
