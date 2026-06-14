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

		// Try to read platform and year from sibling <td> cells.
		platform, year := "", 0
		row := s.Closest("tr")
		if row.Length() > 0 {
			cells := row.Find("td")
			platform, year = extractPlatformYear(cells, title)
		}

		entries = append(entries, CatalogEntry{
			Title:     title,
			SourceURL: abs,
			Platform:  platform,
			Year:      year,
		})
	})
	return entries
}

// extractPlatformYear heuristically reads platform and year from table row cells.
// khinsider browse rows: [#] [icon] [title] [platform] [tracks] [type] [year]
// We skip cells that contain the title and look for the platform and a 4-digit year.
func extractPlatformYear(cells *goquery.Selection, title string) (platform string, year int) {
	var texts []string
	cells.Each(func(_ int, td *goquery.Selection) {
		t := strings.TrimSpace(td.Text())
		if t != "" && t != title {
			texts = append(texts, t)
		}
	})
	// Walk right-to-left: last numeric-looking cell ≥ 1980 is the year.
	for i := len(texts) - 1; i >= 0; i-- {
		if y, err := strconv.Atoi(texts[i]); err == nil && y >= 1980 && y <= 2035 {
			year = y
			// Platform is usually the cell just after the title cell — heuristic: shortest text before year.
			if i > 0 {
				candidate := texts[i-1]
				// Skip if it looks like a track count (pure number) or album type.
				if _, err := strconv.Atoi(candidate); err != nil && len(candidate) < 60 {
					platform = candidate
				}
			}
			break
		}
	}
	return
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
