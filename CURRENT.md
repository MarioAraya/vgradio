# CURRENT — VGRadio

Última sesión: 2026-07-17

## En progreso

### Offline downloads + badges "Descargado" (solo macOS)

Feature pedida: distintivo visual pa tracks/álbumes descargados + nuevo menú "Descargado" (como Favoritos). Alcance acotado a macOS (web queda sin tocar — no hay filesystem real en browser).

**Contexto recopilado:**
- `OfflineStore.swift` ya existía sin trackear al empezar la sesión (base: folder local elegido por usuario, reachability check, toggle modo offline). Solo guardaba IDs de tracks descargados, sin metadata — no alcanzaba pa agrupar por álbum como Favoritos.
- Patrón de referencia: `FavoritesStore.swift` + `FavoritesView.swift` (grouped por álbum, persistencia, empty state).
- Sidebar/nav: `SidebarItem` enum en `ContentView.swift`, filas en `SidebarView.swift`.
- Hay **dos sistemas de descarga distintos** en `DetailTrackRow` (`AlbumDetailView.swift`): botón ⬇ (`downloadTrack` → `POST /tracks/{id}/fetch`, cachea en **servidor**, no toca la Mac) y botón ☁️✓ nuevo (`offline.downloadOffline`, guarda mp3 en carpeta local elegida). Usuario los confundió inicialmente — se resolvió con tooltips más explícitos, no fusión (decisión: dejar ambos, aclarar con `help()`).
- Bug reportado y arreglado: cover faltante en player bar al reproducir desde Favorites/Descargado — causa: `FavoriteTrack.coverUrl`/`DownloadedTrack.coverUrl` puede venir vacío (guardado en momento sin covers cargados). Fix: fallback a `LibraryStore.albums.first(where: id)?.coverUrls` si `coverUrl` viene vacío, en `FavoritesView.swift` y `DownloadedView.swift`.
- Bug reportado "no suena nada al doble-click" — resultó ser build viejo sin compilar (el SSD externo con Xcode, `/Volumes/ExtDevDisk`, estaba desmontado). Una vez compilado y confirmado: streaming remoto funciona normal cuando NO está en modo offline; solo bloquea si `effectiveOfflineMode` (toggle manual o backend inalcanzable).

**Decisiones tomadas (implementadas):**
- `OfflineStore` ahora persiste `[DownloadedTrack]` (JSON en UserDefaults, no solo IDs) con metadata completa (name, albumId, albumTitle, platform, year, durationSec, coverUrl, index) — necesario pa poder agrupar por álbum en la nueva vista.
- Nuevo modelo `DownloadedTrack` en `Models.swift` (mismo shape que `FavoriteTrack` + `index`).
- `OfflineStore.downloadOffline(_:album:)` ahora requiere `album: AlbumSummary` (antes solo `Track`) — call site actualizado en `AlbumDetailView.swift`.
- Nuevas funciones: `downloadedCount(albumID:)`, `isAlbumDownloaded(albumID:totalTracks:)`, `grouped` (computed, mismo patrón que `FavoritesStore.grouped`).
- Nueva vista `DownloadedView.swift` (clon de `FavoritesView.swift`, agrupado por álbum, botón quitar descarga en vez de estrella).
- Badge álbum: círculo verde `checkmark.icloud.fill` sobre la portada en `AlbumCard` (grid) y junto al título en `AlbumListRow` (lista) — visible solo si `isAlbumDownloaded` (todos los tracks del álbum descargados localmente).
- Item nuevo en sidebar: "Descargado" (ícono `checkmark.icloud`), entre Favorites y Recently Played. `SidebarItem.downloaded` en `ContentView.swift`.

**Preguntas pendientes antes de continuar:**
1. Ninguna bloqueante. Falta: probar interactivamente el flujo completo (descargar track → verificar aparece en "Descargado" → verificar badge álbum cuando se completan todos los tracks → quitar descarga) y commitear.

## Completado esta sesión

- [x] Modelo `DownloadedTrack` en `Models.swift`
- [x] `OfflineStore.swift`: persistencia con metadata (JSON), `grouped`, `downloadedCount`, `isAlbumDownloaded`
- [x] `DownloadedView.swift` (vista nueva, agrupada por álbum, con "Play all" y quitar descarga)
- [x] Sidebar: item "Descargado" (`ContentView.swift`, `SidebarView.swift`)
- [x] Badge álbum descargado en `LibraryView.swift` (`AlbumCard` grid + `AlbumListRow` lista)
- [x] Tooltips diferenciados pa botones ⬇ (server cache) vs ☁️✓ (offline local) en `AlbumDetailView.swift`
- [x] Fix cover faltante en Favorites/Descargado al reproducir (fallback a `LibraryStore`)
- [x] Build release confirmado OK (con `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer`), app relanzada y probada por usuario

## Pendiente (próximos pasos inmediatos)

- [ ] **Probar interactivamente** el flujo completo de "Descargado" (badge álbum, quitar descarga, cover fix) — usuario confirmó audio funciona pero no confirmó explícitamente el fix de cover ni el badge de álbum
- [ ] **Commitear cambios** — sin commitear: todo lo de arriba + cambios previos de sesión anterior (Sidebar.svelte, UserMenu.svelte, +layout.svelte, albums/[id]/+page.svelte — UI colapsable, sin relación con offline) + `AlbumDetailView.swift`/`SettingsView.swift` (sección OFFLINE en Settings)
- [ ] **Push pendiente** — verificar cuántos commits adelante de `origin/main` tras commitear
- [ ] Resto de pendientes de sesión anterior sigue igual (ver abajo)

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] **Filtro Library en web** — paridad con macOS (barra de búsqueda en `/library`, Ctrl+F)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Cover en Now Playing (menu bar widget)** — muestra placeholder gris
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider** — ver detalle en notas técnicas abajo
- [ ] **Mini-covers en Browse/catalog search** — ver detalle en notas técnicas abajo
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos

## Notas

### Build macOS requiere SSD externo montado

Xcode vive en `/Volumes/ExtDevDisk/Xcode.app` (CommandLineTools solo no compila — falla con "Invalid manifest" / symbols not found). Si el SSD se desmonta a mitad de sesión, `swift build` falla silenciosamente distinto (a veces "missing DEVELOPER_DIR", a veces "Permission denied" en `/Volumes/ExtDevDisk`). Verificar con `ls /Volumes/ExtDevDisk/Xcode.app/Contents/Developer` antes de compilar.

```bash
cd VGRadio && DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build -c release
pkill -x VGRadio 2>/dev/null; sleep 0.3
cp .build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app
```

### Detalle técnico: scrapear catálogo completo khinsider

3 modos: (1) por consola (revisar `catalog/syncer.go`, ya hay letra/consola parcial), (2) por año (`/game-soundtracks/year/2026`), (3) full catalog (`/game-soundtracks`, 102971 álbumes, 206 páginas). Necesita sección tipo "por descargar/scrapear" (similar a wishlist) pa trackear qué falta bajar.

### Detalle técnico: mini-covers en Browse/catalog search

`CatalogEntry` (`backend/internal/scraper/catalog.go:14`) no tiene campo cover — `extractCatalogEntries` nunca capturó thumb URL (solo el album detail page trae covers). Fix: agregar `CoverThumbURL` a `CatalogEntry`, parsear `<img>` thumb, columna nueva en tabla `catalog`, actualizar `SearchCatalog`/`CountCatalog`, grid UI en Browse (macOS/web).

### Infraestructura homelab

| Servicio    | Host            | URL                           |
|-------------|-----------------|-------------------------------|
| Gitea       | 192.168.0.103   | http://192.168.0.103:3000     |
| Drone CI    | 192.168.0.103   | https://drone.lab             |
| Registry    | 192.168.0.103   | 192.168.0.103:5000 (HTTP)     |
| Traefik     | 192.168.0.104   | —                             |
| VGRadio web | 192.168.0.104   | https://vgradio.lab           |
| VGRadio API | 192.168.0.104   | https://vgradio-api.lab       |

**Drone token:** `ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4`

### Cómo re-migrar datos (si se necesita)

```bash
bash scripts/migrate-to-homelab.sh
# Si falla permisos en volumen, usar:
ssh maaya@192.168.0.104 "bash /tmp/fix-wal.sh"  # (copiar script primero)
```

### CF clearance para Einhander tracks 3+

```bash
# 1. Obtener cf_clearance del browser (DevTools → Cookies → downloads.khinsider.com)
curl -X PUT https://vgradio-api.lab/config/cf-clearance \
  -H 'Content-Type: application/json' -d '{"value":"COOKIE"}'
curl -X POST https://vgradio-api.lab/albums/9ee1fa540f28534f/scrape-tracks
```

### Comandos útiles

```bash
# Build macOS (usar el script, no manual — pero verificar SSD montado primero)
./scripts/build-mac.sh

# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Ver build Drone
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds?limit=3" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4" | python3 -m json.tool
```
