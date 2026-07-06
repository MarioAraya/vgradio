// Package api wires the HTTP layer. Handlers are thin: validate input, delegate to
// store/queue, encode JSON. No business logic here.
package api

import (
	"context"
	"log/slog"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/catalog"
	"github.com/arayama/vgradio-app/backend/internal/jobs"
	"github.com/arayama/vgradio-app/backend/internal/scraper"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

type queuer interface {
	Enqueue(ctx context.Context, albumURL string) (string, error)
	Get(ctx context.Context, jobID string) (*jobs.Job, error)
}

type storer interface {
	Albums(ctx context.Context) ([]store.AlbumSummary, error)
	Album(ctx context.Context, albumID string) (*scraper.Album, error)
	Track(ctx context.Context, trackID string) (*scraper.Track, error)
	TrackAlbumID(ctx context.Context, trackID string) (string, error)
	SetTrackMP3URL(ctx context.Context, trackID, mp3URL string) error
	SetTrackLocalPath(ctx context.Context, trackID, localPath string) error
	Exists(ctx context.Context, albumID string) (bool, error)
	LibraryStats(ctx context.Context) (store.LibraryStats, error)
	AlbumsWithDownloads(ctx context.Context) ([]store.DownloadedAlbum, error)
	ClearAlbumLocalPaths(ctx context.Context, albumID string) ([]string, error)
	DeleteAlbum(ctx context.Context, albumID string) error
	PendingTracks(ctx context.Context) ([]store.PendingTrack, error)
	SearchCatalog(ctx context.Context, q, platform, letter string, offset, limit int) ([]scraper.CatalogEntry, error)
	CountCatalog(ctx context.Context, q, platform, letter string) (int, error)
	Consoles(ctx context.Context) ([]scraper.Console, error)
	RecordPlay(ctx context.Context, trackID, albumID, userID string) error
	RecentHistory(ctx context.Context, limit int, userID string) ([]store.HistoryEntry, error)
	// auth
	CreateUser(ctx context.Context, id, username, email, passwordHash string) error
	GetUserByEmail(ctx context.Context, email string) (*store.User, string, error)
	GetUserByID(ctx context.Context, id string) (*store.User, error)
	ResetPassword(ctx context.Context, email, passwordHash string) error
	CreateSession(ctx context.Context, sessionID, userID string, expiresAt time.Time) error
	GetSession(ctx context.Context, sessionID string) (string, time.Time, error)
	RenewSession(ctx context.Context, sessionID string, expiresAt time.Time) error
	DeleteSession(ctx context.Context, sessionID string) error
	// album favorites
	ToggleFavorite(ctx context.Context, userID, albumID string) (bool, error)
	GetFavorites(ctx context.Context, userID string) ([]store.AlbumSummary, error)
	FavoriteAlbumIDs(ctx context.Context, userID string) (map[string]bool, error)
	// track favorites
	ToggleTrackFavorite(ctx context.Context, userID, trackID string) (bool, error)
	GetFavoriteTracks(ctx context.Context, userID string) ([]store.TrackFavorite, error)
	FavoriteTrackIDs(ctx context.Context, userID string) (map[string]bool, error)
	// playlists
	CreatePlaylist(ctx context.Context, id, userID, name, description string, isPublic bool) (*store.PlaylistSummary, error)
	ListPlaylists(ctx context.Context, userID string) ([]store.PlaylistSummary, error)
	GetPlaylist(ctx context.Context, id string) (*store.PlaylistDetail, error)
	UpdatePlaylist(ctx context.Context, id, name, description string, isPublic bool) error
	DeletePlaylist(ctx context.Context, id string) error
	PlaylistOwner(ctx context.Context, id string) (string, error)
	PlaylistIsPublic(ctx context.Context, id string) (bool, error)
	AddTrackToPlaylist(ctx context.Context, playlistID, trackID string) error
	RemoveTrackFromPlaylist(ctx context.Context, playlistID, trackID string) error
	ReorderPlaylistTracks(ctx context.Context, playlistID string, items []store.ReorderItem) error
}

type trackFetcher interface {
	SongMP3(ctx context.Context, pageURL string) (string, error)
	Download(ctx context.Context, url, destPath string) error
	SetCFClearance(v string)
}

type catalogSyncer interface {
	Start(ctx context.Context) bool
	StartLetter(ctx context.Context, letter string) bool
	SetCFClearance(v string)
	Progress() catalog.SyncProgress
	Top40(ctx context.Context) ([]scraper.Top40Entry, error)
}

type handler struct {
	store   storer
	queue   queuer
	fetcher trackFetcher
	syncer  catalogSyncer
	dataDir string
}

// requestLogger logs method, path, status and latency for every request.
func requestLogger(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusWriter{ResponseWriter: w, code: 200}
		next.ServeHTTP(rw, r)
		// skip noisy catalog-sync poll and cover-file requests
		if r.URL.Path == "/catalog/sync" || strings.HasPrefix(r.URL.Path, "/covers/") {
			return
		}
		log.Info("http", "method", r.Method, "path", r.URL.Path,
			"status", rw.code, "ms", time.Since(start).Milliseconds())
	})
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (sw *statusWriter) WriteHeader(code int) {
	sw.code = code
	sw.ResponseWriter.WriteHeader(code)
}

// NewRouter returns the API router. dataDir is the root for downloaded files.
func NewRouter(s storer, q queuer, f trackFetcher, syn catalogSyncer, dataDir string, log *slog.Logger) http.Handler {
	h := &handler{store: s, queue: q, fetcher: f, syncer: syn, dataDir: dataDir}
	mux := http.NewServeMux()

	// existing routes
	mux.HandleFunc("POST /albums", h.postAlbum)
	mux.HandleFunc("GET /albums", h.getAlbums)
	mux.HandleFunc("GET /albums/{id}", h.getAlbum)
	mux.HandleFunc("GET /jobs/{id}", h.getJob)
	mux.HandleFunc("POST /albums/{id}/scrape-tracks", h.scrapeAlbumTracks)
	mux.HandleFunc("GET /tracks/{id}/stream", h.streamTrack)
	mux.HandleFunc("GET /tracks/{id}/resolve", h.resolveTrackURL)
	mux.HandleFunc("GET /tracks/{id}/download", h.downloadTrack)
	mux.HandleFunc("POST /tracks/{id}/fetch", h.fetchTrackLocal)
	mux.HandleFunc("POST /catalog/sync", h.postCatalogSync)
	mux.HandleFunc("GET /catalog/sync", h.getCatalogSync)
	mux.HandleFunc("GET /catalog", h.getCatalog)
	mux.HandleFunc("GET /catalog/consoles", h.getCatalogConsoles)
	mux.HandleFunc("GET /catalog/top40", h.getTop40)
	mux.HandleFunc("PUT /config/cf-clearance", h.putCFClearance)
	mux.HandleFunc("POST /history", h.postHistory)
	mux.HandleFunc("GET /history", h.getHistory)
	mux.HandleFunc("GET /albums/{id}/covers.zip", h.getCoversZip)
	mux.HandleFunc("GET /stats", h.getStats)
	mux.HandleFunc("GET /health", h.getHealth)
	mux.HandleFunc("GET /albums/downloaded", h.getDownloadedAlbums)
	mux.HandleFunc("DELETE /albums/{id}/local", h.deleteAlbumLocal)
	mux.HandleFunc("DELETE /albums/{id}", h.deleteAlbum)
	mux.HandleFunc("POST /scrape/pending", h.scrapeAllPending)

	// auth routes (public)
	mux.HandleFunc("POST /auth/register", h.postRegister)
	mux.HandleFunc("POST /auth/login", h.postLogin)
	mux.HandleFunc("POST /auth/logout", h.postLogout)
	mux.HandleFunc("GET /auth/me", h.getMe)

	// favorites (require auth)
	mux.HandleFunc("POST /favorites/{id}", requireAuth(h.postFavorite))
	mux.HandleFunc("GET /favorites", requireAuth(h.getFavorites))
	mux.HandleFunc("POST /favorites/tracks/{id}", requireAuth(h.postTrackFavorite))
	mux.HandleFunc("GET /favorites/tracks", requireAuth(h.getFavoriteTracks))

	// playlists
	mux.HandleFunc("GET /playlists", h.getPlaylists)
	mux.HandleFunc("POST /playlists", requireAuth(h.postPlaylist))
	mux.HandleFunc("GET /playlists/{id}", h.getPlaylist)
	mux.HandleFunc("PATCH /playlists/{id}", requireAuth(h.patchPlaylist))
	mux.HandleFunc("DELETE /playlists/{id}", requireAuth(h.deletePlaylist))
	mux.HandleFunc("POST /playlists/{id}/tracks", requireAuth(h.postPlaylistTrack))
	mux.HandleFunc("DELETE /playlists/{id}/tracks/{trackId}", requireAuth(h.deletePlaylistTrack))
	mux.HandleFunc("PUT /playlists/{id}/tracks/reorder", requireAuth(h.putPlaylistReorder))

	// admin
	mux.HandleFunc("POST /admin/reset-password", h.postAdminResetPassword)

	// cover image files
	mux.HandleFunc("/covers/", func(w http.ResponseWriter, r *http.Request) {
		rel := strings.TrimPrefix(r.URL.Path, "/covers/")
		parts := strings.SplitN(rel, "/", 2)
		if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
			http.NotFound(w, r)
			return
		}
		albumID, filename := parts[0], filepath.Base(parts[1])
		http.ServeFile(w, r, filepath.Join(dataDir, albumID, "covers", filename))
	})

	return requestLogger(log, cors(h.authMiddleware(mux)))
}

// cors reflects the request Origin back so cookies work from any origin.
// Uses Vary: Origin so caches don't serve wrong responses.
func cors(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Add("Vary", "Origin")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-Admin-Key")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.ServeHTTP(w, r)
	})
}
