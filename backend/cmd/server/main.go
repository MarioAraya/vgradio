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

	// Fetcher.
	f := fetcher.New(fetcher.Options{
		Delay:         time.Duration(cfg.scrapeDelayMS) * time.Millisecond,
		MaxConcurrent: cfg.maxConcurrentDL,
	})

	// Jobs queue.
	q := jobs.NewQueue(s, f, cfg.dataDir, cfg.workers)

	// Catalog syncer.
	syn := catalog.New(s, f, log)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go q.Start(ctx)
	log.Info("scrape queue started", "workers", cfg.workers)

	// HTTP server.
	srv := &http.Server{
		Addr:         cfg.addr,
		Handler:      api.NewRouter(s, q, f, syn, cfg.dataDir),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
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
}

func loadConfig() config {
	return config{
		addr:            envStr("VGRADIO_ADDR", ":8080"),
		dataDir:         envStr("VGRADIO_DATA_DIR", "./data"),
		scrapeDelayMS:   envInt("VGRADIO_SCRAPE_DELAY_MS", 500),
		maxConcurrentDL: envInt("VGRADIO_MAX_CONCURRENT_DL", 4),
		workers:         envInt("VGRADIO_WORKERS", 4),
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
