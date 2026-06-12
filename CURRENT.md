# CURRENT — VGRadio

Última sesión: 2026-06-12

> Estado de implementación para retomar entre sesiones.
> Specs: `docs/SPEC-WEB.md`, `backend/SPEC.md`, `docs/API.md`.
> Test inventory: `docs/TESTS.md`.

---

## Completado esta sesión

- [x] **Cover carousel + lightbox** (`4dee69e`) — swipe, hover arrows, click abre modal fullscreen con imágenes `_orig`
- [x] **Lightbox first-open fix** (`566c289`) — muestra display inmediatamente, carga orig en background (sin blank flash)
- [x] **Favorites album cover** (`566c289`) — thumbnail 60px en cada grupo de álbum
- [x] **Nav arrows no abren lightbox** (`0528d3c`) — stopPropagation en pointer events
- [x] **Error de stream → skip + toast** (`0528d3c`) — listener `error` en `<audio>`, salta al siguiente track y muestra toast rojo
- [x] **Hide button outline-only** (`2c7faef`) — `👎` gris por defecto, amarillo en hover/activo
- [x] **Hidden tracks excluidos del queue** (`2c7faef`) — `playAll()` y `playTrack()` filtran `$hidden`
- [x] **Console chips wrap 3 filas** (`57b0aaf`) — `flex-wrap: wrap` en lugar de scroll horizontal
- [x] **Console counts dinámicos** (`57b0aaf`) — subquery COUNT desde `catalog_entries` en lugar de `album_count` estático
- [x] **Scrape por consola en sync** (`57b0aaf`) — syncer ahora scrapea cada página de consola y setea `platform=c.Name` exacto
- [x] **Fix import button Browse** (`3bd5150`) — URL doble-prefijada corregida (`sourceUrl` ya es absoluta)
- [x] **40 unit tests + 10 E2E** (`9631753`) — Vitest + Playwright, todos pasando. Sin backend requerido en E2E.
- [x] **docs/TESTS.md** (`949d024`) — inventario completo de tests con tablas

---

## Pendiente (próximos pasos)

- [ ] **Push a Gitea** — `git push gitea web` (falló en sesión anterior: `.103:3000` sin respuesta)
- [ ] **Probar Sync Catalog** — el nuevo scrape por consola es más lento (N consolas × 1 request), verificar que no haya timeouts ni bans de Cloudflare
- [ ] **Recently played view** — sidebar link existe, vista es stub vacío
- [ ] **Settings view** — backend URL configurable desde UI (hoy solo via `localStorage` manual o `VGRADIO_ADDR`)
- [ ] **Deploy VPS** — backend + frontend en servidor (Hetzner u otro)
- [ ] **Tests de backend Go** — cero tests en `backend/`

---

## Notas

### Comandos

- Backend: `cd backend && go run ./cmd/server` (puerto 8080)
- Backend logs background: `go run ./cmd/server > /tmp/vgradio.log 2>&1 &` luego `tail -f /tmp/vgradio.log`
- Web dev: `cd web && npm run dev` (puerto 5173)
- Unit tests: `cd web && npm test`
- E2E tests: `cd web && npm run test:e2e` (levanta dev server automático, no requiere backend)
- Push: `git push gitea web` (Gitea en `.103:3000`)

### LAN

- Frontend usa `window.location.hostname:8080` — abrir con IP del host (no localhost) para acceso LAN
- F5 mata el audio — limitación browser. Navegar con clicks no interrumpe.

### Arquitectura de covers

- `cover_N.ext` — display (≤400px), servido en `/covers/<id>/cover_N.ext`
- `cover_N_orig.ext` — original, servido en `/covers/<id>/cover_N_orig.ext`
- Lightbox carga orig en background con `new Image()`, fallback a display si 404
- ZIP descarga todos los `_orig`

### Catalog sync (actualizado)

3 fases:
1. A-Z + 0-9 browse pages → `catalog_entries` con platform del HTML (heurístico)
2. `/console-list` → tabla `consoles` con nombres y URLs
3. Por cada consola → scrapea su página, setea `platform = c.Name` exacto en `catalog_entries`

La fase 3 hace la búsqueda/filtro por consola exacta. Es lenta (1 request/consola ×N).
Console counts en UI son dinámicos (subquery COUNT) — no dependen de `album_count` estático.

### Tests

- **Unit (Vitest)**: 40 tests, 5 archivos en `web/src/lib/**/*.test.ts`
- **E2E (Playwright)**: 10 tests, 2 archivos en `web/e2e/`
- Inventario completo: `docs/TESTS.md`
- `vi.resetModules()` en `beforeEach` — stores son singletons, necesario para aislar tests

### macOS client

- Rama: `main`
- Build: `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build` (desde `VGRadio/`)
