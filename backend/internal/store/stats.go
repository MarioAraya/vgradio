package store

import "context"

// LibraryStats holds aggregate counts for the library.
type LibraryStats struct {
	Albums     int `json:"albums"`
	Tracks     int `json:"tracks"`
	Scraped    int `json:"scraped"`
	Downloaded int `json:"downloaded"`
	Pending    int `json:"pending"`
}

func (s *Store) LibraryStats(ctx context.Context) (LibraryStats, error) {
	var st LibraryStats
	err := s.db.QueryRowContext(ctx, `
		SELECT
			(SELECT COUNT(*) FROM albums),
			COUNT(*),
			COALESCE(SUM(CASE WHEN mp3_url  != '' THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN local_path != '' THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN mp3_url = '' AND page_url != '' THEN 1 ELSE 0 END), 0)
		FROM tracks`).Scan(&st.Albums, &st.Tracks, &st.Scraped, &st.Downloaded, &st.Pending)
	return st, err
}
