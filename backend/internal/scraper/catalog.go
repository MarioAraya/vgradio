package scraper

import (
	"bytes"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// CatalogEntry is a minimal album record from a browse or console listing page.
type CatalogEntry struct {
	Title     string
	SourceURL string // absolute URL to the album page
	Platform  string
	AlbumType string
	Year      int
}

// Console is a platform/console entry from the console-list page.
type Console struct {
	Name       string
	Slug       string // URL path segment, e.g. "nintendo-snes"
	URL        string // absolute URL to the console listing page
	AlbumCount int
}

var reParenCount = regexp.MustCompile(`\((\d[\d,]*)\)\s*$`)

// ParseBrowsePage parses an A-Z or 0-9 browse page and returns catalog entries.
// URL pattern: https://downloads.khinsider.com/game-soundtracks/browse/A
func ParseBrowsePage(html []byte, sourceURL string) ([]CatalogEntry, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, _ := url.Parse(sourceURL)
	return extractCatalogEntries(doc, base), nil
}

// ParseConsoleAlbums parses a console-specific listing page (e.g. /game-soundtracks/nintendo-snes).
func ParseConsoleAlbums(html []byte, sourceURL string) ([]CatalogEntry, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, _ := url.Parse(sourceURL)
	return extractCatalogEntries(doc, base), nil
}

// ParseConsoleList parses the /console-list page and returns all consoles.
func ParseConsoleList(html []byte, sourceURL string) ([]Console, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, _ := url.Parse(sourceURL)
	var consoles []Console
	seen := map[string]bool{}

	doc.Find("a[href]").Each(func(_ int, s *goquery.Selection) {
		href, _ := s.Attr("href")
		if !strings.Contains(href, "/game-soundtracks/") || strings.Contains(href, "/album/") || strings.Contains(href, "/browse/") {
			return
		}
		abs := absURL(base, href)
		// Extract slug: last path segment.
		parts := strings.Split(strings.TrimRight(href, "/"), "/")
		slug := parts[len(parts)-1]
		if slug == "" || slug == "game-soundtracks" || seen[slug] {
			return
		}
		seen[slug] = true

		// Try to extract count from text like "Nintendo SNES (3266)"
		text := strings.TrimSpace(s.Text())
		if text == "" {
			// Try parent element text.
			text = strings.TrimSpace(s.Parent().Text())
		}
		name, count := parseNameCount(text, slug)
		consoles = append(consoles, Console{
			Name:       name,
			Slug:       slug,
			URL:        abs,
			AlbumCount: count,
		})
	})
	return consoles, nil
}

// extractCatalogEntries finds album links in any khinsider listing page.
// khinsider uses <a href="/game-soundtracks/album/..."> for album links.
func extractCatalogEntries(doc *goquery.Document, base *url.URL) []CatalogEntry {
	var entries []CatalogEntry
	seen := map[string]bool{}

	doc.Find(`a[href*="/game-soundtracks/album/"]`).Each(func(_ int, s *goquery.Selection) {
		href, _ := s.Attr("href")
		if href == "" {
			return
		}
		// Skip icon links (no visible text) without poisoning the seen map.
		title := strings.TrimSpace(s.Text())
		if title == "" {
			return
		}
		abs := absURL(base, href)
		if seen[abs] {
			return
		}
		seen[abs] = true

		// Try to read platform, type and year from sibling <td> cells.
		platform, albumType, year := "", "", 0
		row := s.Closest("tr")
		if row.Length() > 0 {
			cells := row.Find("td")
			platform, albumType, year = extractPlatformYearType(cells, title)
		}

		entries = append(entries, CatalogEntry{
			Title:     title,
			SourceURL: abs,
			Platform:  platform,
			AlbumType: albumType,
			Year:      year,
		})
	})
	return entries
}

// extractPlatformYearType heuristically reads platform, albumType and year from table row cells.
// khinsider browse rows: [#] [icon] [title] [platform] [tracks] [type] [year]
func extractPlatformYearType(cells *goquery.Selection, title string) (platform, albumType string, year int) {
	var texts []string
	cells.Each(func(_ int, td *goquery.Selection) {
		t := strings.TrimSpace(td.Text())
		if t != "" && t != title {
			texts = append(texts, t)
		}
	})
	// Walk right-to-left: last cell that parses as 1980–2035 is the year.
	for i := len(texts) - 1; i >= 0; i-- {
		y, err := strconv.Atoi(texts[i])
		if err != nil || y < 1980 || y > 2035 {
			continue
		}
		year = y
		// i-1: album type (Gamerip, Soundtrack, Compilation…)
		if i >= 1 {
			if _, e := strconv.Atoi(texts[i-1]); e != nil && len(texts[i-1]) < 40 {
				albumType = texts[i-1]
			}
		}
		// i-2: track count (numeric) — skip. Scan left for first non-numeric = platform.
		for j := i - 2; j >= 0; j-- {
			if _, e := strconv.Atoi(texts[j]); e != nil && len(texts[j]) < 60 {
				platform = texts[j]
				break
			}
		}
		break
	}
	return
}

// Top40Entry is a ranked album entry from the /top40 weekly chart page.
type Top40Entry struct {
	Rank      int
	Title     string
	SourceURL string
	ThumbURL  string
}

// ParseTop40 parses the /top40 page and returns the ranked chart entries.
func ParseTop40(html []byte, sourceURL string) ([]Top40Entry, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, _ := url.Parse(sourceURL)
	var out []Top40Entry
	doc.Find("table#top40 tr").Each(func(_ int, row *goquery.Selection) {
		cells := row.Find("td")
		if cells.Length() < 3 {
			return
		}
		rankText := strings.TrimSuffix(strings.TrimSpace(cells.Eq(1).Text()), ".")
		rank, err := strconv.Atoi(rankText)
		if err != nil {
			return
		}
		link := cells.Eq(2).Find("a").First()
		title := strings.TrimSpace(link.Text())
		href, _ := link.Attr("href")
		if title == "" || href == "" {
			return
		}
		thumb, _ := cells.Eq(0).Find("img").Attr("src")
		out = append(out, Top40Entry{
			Rank:      rank,
			Title:     title,
			SourceURL: absURL(base, href),
			ThumbURL:  absURL(base, thumb),
		})
	})
	return out, nil
}

// Top12Entry is a ranked album entry from a platform page's "Top 12 [Platform]
// Albums" box (e.g. https://downloads.khinsider.com/game-soundtracks/playstation).
type Top12Entry struct {
	Rank      int
	Title     string
	SourceURL string
	ThumbURL  string
}

// ParseTop12Platform parses a platform listing page and returns its "Top 12
// [Platform] Albums" box. The box is a <table> of <td class="albumIconLarge">
// cells (rank order, top-left to bottom-right), distinct from the full
// album-list table further down the page (class "albumList").
func ParseTop12Platform(html []byte, sourceURL string) ([]Top12Entry, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(html))
	if err != nil {
		return nil, err
	}
	base, _ := url.Parse(sourceURL)
	var out []Top12Entry
	doc.Find("td.albumIconLarge").Each(func(i int, cell *goquery.Selection) {
		link := cell.Find("a").First()
		href, _ := link.Attr("href")
		title := strings.TrimSpace(link.Find("p").Text())
		thumb, _ := link.Find("img").Attr("src")
		if href == "" || title == "" {
			return
		}
		out = append(out, Top12Entry{
			Rank:      i + 1,
			Title:     title,
			SourceURL: absURL(base, href),
			ThumbURL:  absURL(base, thumb),
		})
	})
	return out, nil
}

// parseNameCount extracts name and count from strings like "Nintendo SNES (3266)" or "Nintendo SNES".
func parseNameCount(text, slug string) (name string, count int) {
	if m := reParenCount.FindStringSubmatch(text); len(m) == 2 {
		count, _ = strconv.Atoi(strings.ReplaceAll(m[1], ",", ""))
		name = strings.TrimSpace(text[:len(text)-len(m[0])])
	} else {
		name = text
	}
	if name == "" {
		// Fallback: humanise slug.
		name = strings.ReplaceAll(strings.ReplaceAll(slug, "-", " "), "_", " ")
		parts := strings.Fields(name)
		for i, p := range parts {
			if len(p) > 0 {
				parts[i] = strings.ToUpper(p[:1]) + p[1:]
			}
		}
		name = strings.Join(parts, " ")
	}
	return
}
