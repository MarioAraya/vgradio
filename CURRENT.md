# CURRENT — VGRadio

Última sesión: 2026-06-06

> Estado de implementación para retomar entre sesiones. Pareja con `features.json`.
> Specs: `SPEC.md`, `backend/SPEC.md`, `VGRadio/SPEC.md`, `docs/API.md`.

## En progreso

### Backend Go — scraper (TDD)

Construyendo el backend scraper API por capas con TDD. Scraper terminado; sigue `store`.

**Contexto recopilado (sitio origen = khinsider):**
- mp3 directo **NO** está en la página de álbum. Cada track linkea a una **página de
  canción** que tiene el mp3 en `<audio id="audio" src>` (estático, sin JS). → scrape 2 pasos.
- Sin número de track en el HTML → `Track.Index` = posición (1..N).
- hrefs vienen doble-encoded (`%2520` = espacio); se preservan tal cual, funcionan.
- mp3 reales servidos desde `*.vgmtreasurechest.com`.
- Fixture real: `kirby-planet-robobot-gamerip` = 181 tracks, 1 cover.

**Decisiones tomadas (recién implementadas):**
- Parser **puro** (`[]byte HTML → struct`), sin red/disco → 100% testeable con fixtures.
- HTML parsing con **goquery** (`PuerkitoBio/goquery`); metadata por regex sobre labels.
- `Track`: añadidos `PageURL` (página canción) y `SongID`; `MP3URL` se resuelve aparte.
- Module path Go: `github.com/arayama/vgradio-app/backend`.
- Cache backend confirmado: filesystem (audio) + SQLite (metadata).
- Entrega: stream (Range) + descarga. Cliente SwiftUI macOS 14+.

**Preguntas pendientes antes de continuar:**
1. ¿Siguiente capa: `store` (cache + idempotencia) o `fetcher`/`api`? (recomendado: `store`).
2. Persona 5 tiene metadata multi-plataforma / multi-disco — ¿`Platform` string único o `[]string`?
   (hoy captura solo el primero; revisar al scrapear Persona 5).

## Completado esta sesión

- [x] SDD: specs maestro + backend + cliente + contrato API (`d7debc7`).
- [x] Feature favoritos (★) en v1 single-user; playlists/share a fase 2 (`1b78b28`).
- [x] Módulo Go + goquery; tipos dominio (Album/Track/Cover/Comment).
- [x] **TDD scraper GREEN** (`8401840`): `ParseAlbum` + `ParseSongMP3`, 4 tests pasan
      contra fixture real Kirby (181 tracks). `gofmt`/`go vet` limpios.
- [x] `docs/seed-urls.md` con URLs semilla + nota de scraping 2 pasos.

## Pendiente (próximos pasos inmediatos)

- [ ] **`internal/store`** (TDD): SQLite (albums/tracks/covers/comments/jobs) + filesystem.
      Tests: guardar/releer Album idéntico; `Exists(albumID)` true; idempotencia (no re-scrape).
- [ ] `internal/fetcher`: descarga mp3/covers con throttle + context (test de humo).
- [ ] `internal/jobs`: cola async goroutines (pending/running/done/failed).
- [ ] `internal/api`: handlers HTTP (`httptest`): POST /albums 202, GET /albums/:id, Range 206.
- [ ] `cmd/server/main.go`: wiring + arranque.
- [ ] Validación anti-SSRF de URL de entrada (boundary "always").
- [ ] Cliente SwiftUI: arrancar tras backend mínimo usable.

## Notas

- albumID = hash estable de sourceURL (definido en spec, aún no implementado).
- `Number of Files: 181` calza exacto con tracks parseados → buena señal del parser.
- Fixtures en `backend/internal/scraper/testdata/{album,song}.html` (commiteados).
- Comando bajar fixture: `curl -sL -A "Mozilla/5.0" <url> -o <archivo>`.
- Tests: `cd backend && go test ./...`. Fmt: `gofmt -l .` (debe salir vacío).
- `.gitignore` excluye `backend/data/` (cache runtime, no versionar).
