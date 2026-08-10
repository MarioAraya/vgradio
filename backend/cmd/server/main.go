package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/api"
	"github.com/arayama/vgradio-app/backend/internal/catalog"
	"github.com/arayama/vgradio-app/backend/internal/connect"
	"github.com/arayama/vgradio-app/backend/internal/fetcher"
	"github.com/arayama/vgradio-app/backend/internal/jobs"
	"github.com/arayama/vgradio-app/backend/internal/store"
)

func main() {
	cfg := loadConfig()
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	// Store (SQLite + filesystem).
	if err := os.MkdirAll(cfg.dataDir, 0o755); err != nil {
		log.Error("create data dir", "err", err)
		os.Exit(1)
	}
	s, err := store.New(filepath.Join(cfg.dataDir, "vgradio.db"))
	if err != nil {
		log.Error("open store", "err", err)
		os.Exit(1)
	}

	// cf_clearance: prefer the value persisted on disk (set via PUT /config/cf-clearance
	// and kept up to date across restarts) over the env var, which only reflects
	// whatever was true at deploy time.
	cfClearance := cfg.cfClearance
	if b, err := os.ReadFile(filepath.Join(cfg.dataDir, "cf_clearance.txt")); err == nil {
		cfClearance = string(b)
	}

	// Fetcher.
	f := fetcher.New(fetcher.Options{
		Delay:         time.Duration(cfg.scrapeDelayMS) * time.Millisecond,
		MaxConcurrent: cfg.maxConcurrentDL,
		CFClearance:   cfClearance,
	})

	// Jobs queue.
	q := jobs.NewQueue(s, f, cfg.dataDir, cfg.workers, log)

	// Catalog syncer.
	syn := catalog.New(s, log)
	syn.SetCFClearance(cfClearance)

	// Connect hub (remote control across a user's devices).
	hub := connect.New(log, s)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go q.Start(ctx)
	log.Info("scrape queue started", "workers", cfg.workers)

	go runWeeklyCatalogSync(ctx, syn, log)

	// Expires dead devices and flushes playback state on a ticker.
	go hub.Run(ctx)

	// HTTP server.
	srv := &http.Server{
		Addr:         cfg.addr,
		Handler:      api.NewRouter(s, q, f, syn, hub, cfg.dataDir, log),
		ReadTimeout: 15 * time.Second,
		// No server-wide WriteTimeout: it also capped audio streams, zips and the
		// synchronous scrape endpoints. The cap is applied per-route by the
		// writeDeadline middleware (see api.isLongWrite).
		IdleTimeout: 120 * time.Second,
	}

	go func() {
		log.Info("listening", "addr", cfg.addr, "data_dir", cfg.dataDir)
		if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			log.Error("server error", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	log.Info("shutting down…")

	shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutCtx); err != nil {
		log.Error("shutdown error", "err", err)
	}
	log.Info("bye")
}

type config struct {
	addr            string
	dataDir         string
	scrapeDelayMS   int
	maxConcurrentDL int
	workers         int
	cfClearance     string
}

func loadConfig() config {
	return config{
		addr:            envStr("VGRADIO_ADDR", ":8080"),
		dataDir:         envStr("VGRADIO_DATA_DIR", "./data"),
		scrapeDelayMS:   envInt("VGRADIO_SCRAPE_DELAY_MS", 500),
		maxConcurrentDL: envInt("VGRADIO_MAX_CONCURRENT_DL", 4),
		workers:         envInt("VGRADIO_WORKERS", 4),
		cfClearance:     envStr("VGRADIO_CF_CLEARANCE", ""),
	}
}

func envStr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: %s=%q is not an integer, using default %d\n", key, v, def)
		return def
	}
	return n
}

// runWeeklyCatalogSync triggers a full catalog re-scrape once a week for as long
// as ctx is alive. It does not run one immediately on startup — only on each tick —
// so restarts don't cause an unplanned extra scrape.
func runWeeklyCatalogSync(ctx context.Context, syn *catalog.Syncer, log *slog.Logger) {
	ticker := time.NewTicker(7 * 24 * time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if !syn.Start(ctx) {
				log.Warn("weekly catalog sync: skipped, already running")
				continue
			}
			log.Info("weekly catalog sync: started")
			go logSyncResult(ctx, syn, log)
		}
	}
}

// logSyncResult polls until the sync finishes and logs a summary. Cheap poll,
// runs once a week, no need for a channel-based signal from the syncer.
func logSyncResult(ctx context.Context, syn *catalog.Syncer, log *slog.Logger) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(30 * time.Second):
		}
		p := syn.Progress()
		if !p.Running {
			log.Info("weekly catalog sync: finished",
				"entries", p.Entries, "consoles", p.Consoles, "errors", p.Errors)
			return
		}
	}
}
