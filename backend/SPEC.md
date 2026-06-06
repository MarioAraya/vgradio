# SPEC — Backend (scraper API, Go)

> API HTTP que scrapea álbumes de música, cachea resultado (filesystem + SQLite)
> y sirve metadata + audio al cliente. Asíncrono con goroutines.
> Padre: [`../SPEC.md`](../SPEC.md). Contrato HTTP: [`../docs/API.md`](../docs/API.md).

---

## 1. Objetivo

Recibir una **URL de álbum**, scrapearla **una sola vez** de forma asíncrona,
persistir metadata + tracks + carátulas, y exponer:
- consulta de álbumes/tracks cacheados,
- estado del job de scrape,
- stream (Range) y descarga de cada `.mp3`.

---

## 2. Modelo de dominio

```
Album
  id            string   (hash de la URL fuente, estable)
  sourceURL     string
  title         string
  altTitle      string   (ej. título japonés)
  platform      string   (GC, SNES, ...)
  year          int
  developer     string
  publisher     string
  albumType     string   (Gamerip, Soundtrack, ...)
  description   string
  covers        []Cover
  tracks        []Track
  comments      []Comment
  scrapedAt     time
Cover    { url, localPath, width, height }
Track    { id, index, name, durationSec, sizeBytes, sourceURL, localPath }
Comment  { author, body, postedAt }
ScrapeJob{ id, albumID, status, error, startedAt, finishedAt }
            status ∈ {pending, running, done, failed}

# Fase 1.5 — entrada ligera de catálogo (no requiere scrape completo)
CatalogEntry
  id          string   (hash de sourceURL, == albumID si luego se scrapea)
  title       string
  platforms   []string (3DS, SNES, Arcade, ...)
  albumType   string   (Arrangement, Gamerip, Soundtrack, ...)
  year        int
  thumbUrl    string
  sourceURL   string
  scraped     bool     (true si ya existe Album completo cacheado)
```

---

## 3. Estructura

```
backend/
├── SPEC.md
├── go.mod
├── cmd/
│   └── server/main.go          # wiring + arranque HTTP
└── internal/
    ├── scraper/                # HTML → Album (parsing puro, testeable)
    │   ├── scraper.go
    │   ├── parse.go
    │   └── parse_test.go
    │   └── testdata/album.html # fixture real guardado
    ├── store/                  # SQLite + filesystem (cache)
    │   ├── store.go
    │   ├── sqlite.go
    │   └── store_test.go
    ├── fetcher/                # descarga mp3/covers con throttle + context
    │   └── fetcher.go
    ├── jobs/                   # cola async de scrape (goroutines)
    │   └── jobs.go
    └── api/                    # handlers HTTP
        ├── router.go
        ├── handlers.go
        └── handlers_test.go
```

### Separación
- `scraper` = **puro**: `[]byte HTML → Album` (página de álbum) y `[]byte HTML → []CatalogEntry`
  (páginas índice: Browse All / por letra / por plataforma / Top). Sin red, sin disco → 100% testeable.
- `fetcher` = I/O de red (GET con rate-limit, retries, context cancel).
- `store` = persistencia (SQLite metadata + filesystem audio/covers).
- `jobs` = orquesta: scrape → fetch assets → store, en goroutine, reporta estado.
- `api` = transporte HTTP fino; delega a los demás.

---

## 4. Layout de cache

```
data/
├── vgradio.db                  # SQLite: albums, tracks, covers, comments, jobs
└── audio/
    └── <albumID>/
        ├── cover_0.jpg
        ├── 001_Title.mp3
        └── 002_Menu_Select.mp3
```

Idempotencia: si `albumID` ya existe con `status=done`, devolver caché. Re-scrape solo
con flag `?refresh=true` explícito.

---

## 5. Concurrencia

- Endpoint de scrape encola job y responde `202 Accepted` con `jobID` (no bloquea).
- Worker pool de goroutines procesa jobs; `context` para cancelación/timeout.
- Descarga de N tracks en paralelo con límite (semáforo) + delay entre requests al origen.
- Estado de job consultable por polling (`GET /jobs/:id`).

---

## 6. Comandos

```bash
go run ./cmd/server      # :8080
go test ./...            # unit
go vet ./...
gofmt -l .               # debe salir vacío
```

Config por env: `VGRADIO_ADDR`, `VGRADIO_DATA_DIR`, `VGRADIO_SCRAPE_DELAY_MS`,
`VGRADIO_MAX_CONCURRENT_DL`. Sin hardcodear dominio origen.

---

## 7. Testing (TDD primero)

| Test | Cubre |
|------|-------|
| `scraper.parse_test` | fixture `album.html` → Album con title, year, platform, N tracks, covers, comments. **Núcleo.** |
| `scraper.catalog_test` | fixture `catalog.html` (índice) → `[]CatalogEntry` con title, platforms, type, year, thumb (fase 1.5). |
| `store.store_test` | guardar Album y releerlo igual; `Exists(albumID)` true; idempotencia. |
| `api.handlers_test` | `POST /albums` → 202+jobID; `GET /albums/:id` → 200 JSON; Range en stream → 206. |

Orden TDD v1: `scraper` → `store` → `api`. `fetcher`/`jobs` con tests de humo.

---

## 8. Boundaries

- **Always:** throttle + respetar robots.txt; validar URL (bloquear IPs privadas → anti-SSRF); errores explícitos.
- **Ask first:** añadir headless browser (Chromedp) si el sitio fuera JS-rendered.
- **Never:** re-scrapear sin flag; hardcodear dominio/credenciales; descargas sin límite de concurrencia.

### Suposición a validar
El HTML del sitio origen es **server-rendered** (links `.mp3` presentes en el HTML
inicial). Si fuese renderizado por JS, `scraper` con `net/http`+parser no basta y habría
que evaluar headless browser (ask first). Se confirma guardando un fixture real en `testdata/`.
