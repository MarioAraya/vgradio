# CURRENT — VGRadio

Última sesión: 2026-06-12

## Sin commitear (todo listo para commit)

7 archivos modificados:
- `backend/internal/api/handlers.go` — nuevo endpoint `/resolve?force=1`, handler `resolveTrackURL`
- `web/src/lib/api.ts` — signal en `get`/`post`, `resolveTrackUrl(force)`, `fetchTrack(signal)`, `album(signal)`
- `web/src/lib/stores/player.ts` — fallback 2 niveles (cached → force re-scrape), `fallbackAttempted` Set
- `web/src/lib/components/QueuePanel.svelte` — header clickeable colapsa lista, chevron `▸`/`▾`, current row amarillo
- `web/src/routes/+page.svelte` — play button en hover de cover, AbortController, card amarilla si álbum sonando
- `web/src/routes/albums/[id]/+page.svelte` — current track amarillo en tracklist, fetchTrack con timeout 120s

---

## Completado esta sesión

- [x] **Queue drop indicator** (`803bbd0`) — línea accent al arrastrar, calcula posición por mitad del row
- [x] **Download `_blank` + source link `↗`** (`803bbd0`) — download no reemplaza tab, link fuente junto a Covers
- [x] **Fetch button por track** (`eb69949`) — `⬇` tenue → spinner → descarga local con timeout 120s
- [x] **Fallback stream khinsider** (sin commit) — error en `/stream` → resolve cached → falla → `?force=1` re-scrapea
- [x] **Queue collapse** (sin commit) — header click colapsa/expande lista, `▸`/`▾`
- [x] **Current track amarillo** (sin commit) — tracklist y queue destacan track actual en accent
- [x] **Play button en Library** (sin commit) — botón `▶` circular sobre cover en hover, AbortController
- [x] **Library card amarilla** (sin commit) — card del álbum sonando tiene fondo/título accent
- [x] **AbortController Library** (sin commit) — cancela request anterior si click rápido en otro álbum
- [x] **Backend `/resolve?force=1`** (sin commit) — fuerza re-scrape de MP3 URL de khinsider

---

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear todo** — 7 archivos listos
- [ ] **Push a Gitea** — `git push gitea web`
- [ ] **Probar Sync Catalog** — scrape por consola, verificar CF no bloquea
- [ ] **Recently played view** — sidebar link existe, vista es stub vacío
- [ ] **Settings view** — backend URL configurable desde UI
- [ ] **Deploy VPS**
- [ ] **Tests backend Go**

---

## Notas

### Flujo de stream / fallback (actualizado)

```
audio.src = /tracks/{id}/stream
  → si local: sirve MP3
  → si no: 302 → URL khinsider (puede bloquear CF)

error event en audio:
  1. src contiene /stream → GET /tracks/{id}/resolve (URL cacheada)
     → audio.src = url directo khinsider, retry
  2. src es URL directa y fallbackAttempted.has(id) → GET /tracks/{id}/resolve?force=1
     → re-scrapea khinsider page, nueva URL, retry
  3. todo falla → toast error + skip
```

### Comandos

- Backend: `cd backend && go run ./cmd/server` (puerto 8080)
- Web dev: `cd web && npm run dev` (puerto 5173)
- Unit tests: `cd web && npm test`
- E2E: `cd web && npm run test:e2e`
- Push: `git push gitea web`

### LAN

- Frontend usa `window.location.hostname:8080`
- F5 mata el audio — limitación browser

### macOS client

- Rama: `main`
- Build: `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build`
