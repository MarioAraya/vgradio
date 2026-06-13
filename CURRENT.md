# CURRENT — VGRadio

Última sesión: 2026-06-12

## Sin commitear (listo para commit)

5 archivos modificados:
- `backend/internal/api/handlers.go` — endpoint `POST /albums/{id}/scrape-tracks`, `scraped` field en track response, `GET /tracks/{id}/resolve?force=1`
- `backend/internal/scraper/parse.go` — fix double-encoding `%2520` en `absURL()`
- `web/src/lib/api.ts` — `scrapeAlbumTracks()`, signal en get/post, `resolveTrackUrl(force)`
- `web/src/lib/types.ts` — `scraped?: boolean` en Track
- `web/src/routes/albums/[id]/+page.svelte` — 3 estados visuales por track (not scraped / scraped / downloaded), botón "⚡ Scrape URLs", scrape por track individual

---

## Completado esta sesión

- [x] **Stream fallback 2 niveles** (`c3e0ac5`) — error → resolve cached → force re-scrape khinsider
- [x] **Queue collapse** (`c3e0ac5`) — header click colapsa lista, `▸`/`▾`
- [x] **Play button en Library** (`c3e0ac5`) — `▶` circular en hover de cover, AbortController
- [x] **Current track amarillo** (`c3e0ac5`) — tracklist y queue, fondo + texto accent
- [x] **scrapeAlbumTracks** (sin commit) — `POST /albums/{id}/scrape-tracks` resuelve MP3URLs en batch
- [x] **3 estados visuales por track** (sin commit) — dot verde (local), dot amarillo (scraped), botón `🔗` (sin scrape)
- [x] **scrapeTrack individual** (sin commit) — botón por track para resolver su URL
- [x] **Fix double-encoding khinsider** (sin commit) — `absURL()` hace `PathUnescape` antes de parsear; SQL UPDATE en DB (`%2520`→`%20`, 576 rows)
- [x] **scraped field en API** (sin commit) — `mp3_url != ""` expuesto como `scraped: bool`
- [x] **Memoria guardada** — `feedback_khinsider_double_encoding.md` en memory/

---

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear todo** — 5 archivos listos
- [ ] **Push a Gitea** — `git push gitea web`
- [ ] **Probar Scrape URLs** en álbum con tracks sin scrape (ej: Dracula Battle tracks 214-217)
- [ ] **Recently played view** — sidebar link existe, vista stub vacía
- [ ] **Settings view** — backend URL configurable desde UI
- [ ] **Deploy VPS**
- [ ] **Tests backend Go**

---

## Notas

### Fix khinsider double-encoding

khinsider tiene `%20` en hrefs HTML → `url.Parse` decodifica `%25`→`%` → `String()` re-codifica → `%2520`.
Fix: `url.PathUnescape(href)` antes de `url.Parse` en `absURL()`.
Si reaparece en DB: `SELECT name, page_url FROM tracks WHERE page_url LIKE '%2520%';`
SQL fix: `UPDATE tracks SET page_url = replace(page_url, '%2520', '%20') WHERE page_url LIKE '%2520%';`
Ver memoria: `feedback_khinsider_double_encoding.md`

### 3 estados de track

| Estado | Dot | Botón | Acción |
|--------|-----|-------|--------|
| Not scraped | — | `🔗` gris | `GET /tracks/{id}/resolve` → persiste mp3_url |
| Scraped | 🟡 | `⬇` amarillo | `POST /tracks/{id}/fetch` → descarga local |
| Downloaded | 🟢 | `⬇` verde | link descarga archivo local |

### Comandos

- Backend: `cd backend && go run ./cmd/server` (puerto 8080)
- Web dev: `cd web && npm run dev` (puerto 5173)
- Unit tests: `cd web && npm test`
- E2E: `cd web && npm run test:e2e`
- Push: `git push gitea web`

### LAN

- Frontend usa `window.location.hostname:8080`
- F5 mata el audio — limitación browser
