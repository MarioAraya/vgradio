# CURRENT — VGRadio

Última sesión: 2026-06-06 (sesión 5)

> Estado de implementación para retomar entre sesiones. Pareja con `features.json`.
> Specs: `SPEC.md`, `backend/SPEC.md`, `VGRadio/SPEC.md`, `docs/API.md`.

## En progreso

### UX de tracks — hide + thumbup + covers persistidas

Sesión 5 agregó varias features de UX al player client. Todas compilando, sin XCTest todavía.

**Decisiones tomadas:**
- `CoverPrefsStore` es singleton (no `@Observable`) — no necesita reactividad, AlbumCoverView ya maneja su propio `@State`
- `HiddenTracksStore` es `@Observable` — inyectado via `.environment()` para que los rows reaccionen al toggle
- `PlayerService.hiddenTracks` es opcional (`HiddenTracksStore?`) — se setea en `.onAppear` del WindowGroup
- El header del tracklist cambió ★ → 👍 / 👁 como labels de columna (emojis, discutible)
- Drag-down gesture en `DetailTrackRow` con `minimumDistance: 12` y `translation.height > 20` para ocultar track

**Preguntas abiertas:**
1. ¿Emojis 👍 👁 en header del tracklist se ven bien o cambiar a iconos SF?
2. ¿Al reproducir Play en AlbumDetail, el primer track no-oculto debería ser el primero de la cola o saltar al siguiente no-oculto internamente?

## Completado esta sesión (sesión 5)

- [x] **Cover index persistido por álbum** — `CoverPrefsStore` guarda `[albumID: Int]` en UserDefaults. `AlbumCoverView` recibe `initialIndex`. Library y DetailView leen/escriben. Al hacer Play se restaura el cover guardado.
- [x] **Volumen on hover** — `PlayerBarView.volumeSection`: slider aparece/desaparece animado (`.easeInOut 0.18s`) con `.onHover` en el HStack completo. Ícono siempre visible.
- [x] **Ocultar tracks (swipe down)** — `HiddenTracksStore` persiste en UserDefaults. Gesture drag-down en fila. Botón `arrow.down.to.line` on hover. Track oculto: 45% opacidad, nombre tachado, ícono `eye.slash`. `PlayerService.next()/previous()` los salta automáticamente.
- [x] **Thumbs up on hover** — `DetailTrackRow`: columna favorito muestra `hand.thumbsup` on hover, `hand.thumbsup.fill` si ya es favorito (reemplaza el ★ estático).
- [x] **Play respeta ocultos** — botón Play en AlbumDetail arranca desde el primer track no-oculto.
- [x] Build limpio: `swift build` → `Build complete!` (4.83s)

## Completado sesiones previas

- [x] Backend v1 completo (scraper, store, fetcher, jobs, API, SSRF guard)
- [x] Lazy MP3 resolution en `/stream` — resuelve URL on-demand, cachea, 302
- [x] Servir covers locales: `GET /covers/<albumID>/<filename>`
- [x] DesignSystem tokens reales Lovable (OKLCH→hex), `VGLayout`, `ThinProgressTrack`
- [x] Space bar play/pause (`.onKeyPress(.space)` en `ContentView`)
- [x] AddURLView: Esc dismiss, Import con URL default (DOOM 1997)
- [x] AlbumDetailView: metadata completa (plataformas, catalog, alt titles, developer, publisher)
- [x] Star álbum: `FavoritesStore.addAll/removeAll/isAlbumFavorited`
- [x] AlbumCoverView: hover-nav con flechas ‹ › + dots indicator
- [x] Carátula real en player bar
- [x] Drone CI para backend Go
- [x] Player bar rediseño estilo YT Music: HStack single row, progreso top edge, tiempo inline

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear sesión 5** — `CoverPrefsStore.swift`, `HiddenTracksStore.swift` (nuevos), 6 archivos modificados
- [ ] **Header tracklist** — decidir emojis 👍 👁 vs SF Symbols en columnas del tracklist
- [ ] **XCTest cliente** — `LibraryStore`, `FavoritesStore`, `HiddenTracksStore`, `PlayerService`
- [ ] **client-download** — UI descarga álbum offline (botón AlbumDetail + progreso)
- [ ] **Activar CI** — `GITEA_TOKEN=xxx bash "../1_scripts/homelab deploy/create-gitea-repos.sh"` → push gitea → activar Drone

## Notas

- Build Swift: `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build` (desde `VGRadio/`)
- Error SourceKit "SDK not supported" es mismatch de toolchain, no afecta compilación
- Backend: `cd backend && go run ./cmd/server`
- `CoverPrefsStore.shared.index(for:)` retorna 0 si no hay preferencia guardada (seguro)
- `PlayerService.hiddenTracks` se setea en `.onAppear` del WindowGroup — si se resetea el player antes del onAppear, hiddenTracks será nil (edge case improbable)
- Xcode en SSD externa: `/Volumes/ExtDevDisk/Xcode.app`
