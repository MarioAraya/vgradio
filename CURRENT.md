# CURRENT — VGRadio

Última sesión: 2026-06-08 (sesión 6)

> Estado de implementación para retomar entre sesiones. Pareja con `features.json`.
> Specs: `SPEC.md`, `backend/SPEC.md`, `VGRadio/SPEC.md`, `docs/API.md`.

## En progreso

### Queue drag reorder — 2 archivos sin commitear

`moveInQueue(from:to:)` en PlayerService y QueuePanel reescrito con `List + .onMove`.
Build pasa. Falta commitear.

## Completado esta sesión (sesión 6)

- [x] **Fix build roto** — `FavoritesStore` le faltaban `isAlbumFavorited`, `addAll`, `removeAll(albumID:)` (commit `17a698a`)
- [x] **Streaming sin pre-descarga** — backend `streamTrack`: si no hay `LocalPath`, resuelve `MP3URL` vía scraper on-demand y redirige 302. Frontend quita guard `downloadedIDs` de play y doble-click (commit `17a698a`)
- [x] **Media keys relanzados** — `MPRemoteCommandCenter` (play/pause/toggle/next/prev/seek), `NowPlayingInfo` updates, `MediaPlayer` framework en `Package.swift` (commit `340868d`)
- [x] **Cmd+1–4 shortcuts** — Library/Browse/Favorites/AddURL via hidden buttons (commit `340868d`)
- [x] **Navegar al álbum desde player bar** — click en cover o título navega a `AlbumDetailView` via `LibraryStore.pendingNavigation` (commit `340868d`)
- [x] **Icono hide track** — `arrow.down.to.line`/`eye.slash` → `hand.thumbsdown`/`hand.thumbsdown.fill` (commit `340868d`)
- [x] **Botón Play Next por track** — `PlayerService.playNext()` inserta en `queueIndex+1`. Columna `▶+` en tracklist, hover-only (commit `e739030`)
- [x] **Play all en Favorites** — botón "Play all" en header reemplaza cola con todos los favoritos (commit `e739030`)
- [x] **Queue Panel** — overlay 320×420 sobre player bar: scroll a track actual, remove por fila, waveform en current (commit `73fb1db`)
- [x] **Repeat One** — `RepeatMode` enum (off/all/one), botón cicla con icon `repeat`/`repeat.1` (commit `73fb1db`)
- [x] **Shuffle y Repeat conectados** a `PlayerService` (antes eran `@State` local sin efecto) (commit `73fb1db`)
- [x] **Volumen antes que ★** — reorden secciones player bar (commit `73fb1db`)
- [x] **Slider volumen solo fade** sin efecto slide (uncommitted)
- [x] **Drag reorder en Queue** — `List + ForEach.onMove`, `PlayerService.moveInQueue(from:to:)` — uncommitted

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear** — `PlayerService.swift` + `QueuePanel.swift` (drag reorder + slider fix)
- [ ] **Browse / Catálogo** — vista existe pero sin backend scraper de índice de khinsider
- [ ] **Recently played** — `case recentlyPlayed` en sidebar enum, vista es stub vacío
- [ ] **XCTest cliente** — cero tests en Swift client
- [ ] **Download álbum completo** — solo descarga por track individual hoy
- [ ] **features.json** — actualizar: client-library/addurl/player están done, no "todo"

## Notas

- Build Swift: `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build` (desde `VGRadio/`)
- Backend: `cd backend && go run ./cmd/server`
- Xcode en SSD externa: `/Volumes/ExtDevDisk/Xcode.app`
- `LibraryStore.pendingNavigation` — canal PlayerBar → LibraryView: se setea, ContentView cambia tab a `.library`, LibraryView consume y limpia
- `RepeatMode` enum definido en `PlayerService.swift` antes del `class`
- Queue usa índices como ID en `ForEach` para soportar tracks duplicados (play-next puede duplicar un track)
- Errores SourceKit "Cannot find VGFont in scope" en `QueuePanel.swift` son falsos positivos — build pasa
- `features.json` desactualizado: client-library/addurl/player marcados "todo" pero están done
