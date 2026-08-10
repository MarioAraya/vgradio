# CURRENT — VGRadio

Última sesión: 2026-08-09

## En progreso

Nada a medias. Los 4 ítems de esta sesión quedaron implementados, compilados, desplegados y **confirmados en runtime por el usuario** (incluidas las media keys: ⏭ toma VGRadio, ya no Spotify).

Commiteados en `79ee273`, branch **`fix/album-nav-media-keys-search`** (sin mergear a `main`, sin push).

## Completado esta sesión

### 1. Navegación a álbum desde ⌘K rota (y Back de dos clicks) — mismo bug

**Causa raíz:** `AlbumDetailView` no tenía identidad estable por álbum. SwiftUI reusaba la misma instancia al cambiar de álbum, y `.task { await load() }` corría una sola vez → seguías viendo el álbum anterior. Por eso ⌘K "no hacía nada" y Back necesitaba dos clicks (el primero volvía al álbum previo, pero la pantalla no cambiaba).

- [x] `LibraryView.swift:88` — `.id(album.id)` sobre `AlbumDetailView`
- [x] `AlbumDetailView.swift:65` — `.task(id: summary.id)` en vez de `.task`
- [x] `AlbumDetailView.swift:84` — eliminado `keyboardShortcut("k", .command)` que secuestraba ⌘K para el buscador de tracks. Ahora ⌘K siempre abre el overlay global; ⌘F sigue enfocando el buscador de tracks del álbum

### 2. Botón Thumbs Down en player bar

- [x] `PlayerBarView.swift` — botón junto a la estrella: `hidden.toggle(track.id)` + `player.next()`. `PlayerService.isSkippable` ya filtraba ocultos, así que no vuelve a sonar. Segundo click des-oculta sin saltar. Equivale al atajo ⌘⌫ que ya existía en `ContentView.swift:161`

### 3. Media keys tomaban Spotify (pausado) en lugar de VGRadio (sonando)

`PlayerService.swift`:
- [x] `playCommand`/`pauseCommand` ya no devuelven `.commandFailed` cuando el estado no coincide — devolver failed hace que macOS degrade la app como candidata Now Playing
- [x] Comandos no implementados **deshabilitados explícitamente** (skip/seek fwd-bwd, repeat, shuffle, rating, like, dislike, bookmark, language). Estaban enabled por default sin handler
- [x] `changePlaybackPositionCommand.isEnabled = true` — tenía handler pero nunca se habilitó
- [x] Metadata completa: **artwork** (descarga del cover, cacheado por track ID vía `loadArtworkIfNeeded()`), artista, `MediaType.audio`, `IsLiveStream: false`, `DefaultPlaybackRate`. Esto además cierra el pendiente viejo "Cover en Now Playing muestra placeholder gris"
- [x] `import AppKit` agregado (`NSImage`)

### 4. Buscador ⌘K no traía "DOOM Eternal" con query "doom"

**Verificado contra la DB real:** `q=doom` tiene **162 matches** en `catalog_entries`. El overlay pedía `limit: 8` y el backend ordenaba alfabético → los 8 `Doom` sueltos (3DO, Jaguar, MS-DOS ×2, GBA, Saturn, PS1, SNES) se comían todos los slots.

- [x] `SearchOverlay.swift` — `limit: 8` → `40`; altura de lista 320 → 420px (ya scrolleaba)
- [x] `store/catalog.go:201` — `ORDER BY` rankea por relevancia antes que alfabético: título exacto → empieza con la query → la query arranca una palabra → resto. Sin esto, aun con limit 40 los `Doom (1993)...` copaban los primeros puestos
- [x] Verificado por curl: `/catalog?q=doom&limit=40` devuelve Eternal dentro de los 40

### Builds y deploy

- [x] `swift build -c release` limpio, sin warnings nuevos → binario a `/Applications/VGRadio.app`, app abierta
- [x] `go build ./...` + `go vet ./internal/store/` OK
- [x] Backend recompilado y reiniciado con `backend/update.sh`

## Pendiente (próximos pasos inmediatos)

- [ ] **Decidir qué hacer con `fix/album-nav-media-keys-search`**: merge a `main` (`git checkout main && git merge fix/album-nav-media-keys-search`) y push, o dejarla viva
- [ ] `backend/vgradio-server.log` y `.err.log` están untracked — agregar a `.gitignore`
- [ ] **El resto del working tree sigue sin commitear** (~35 archivos, casi todo `web/`) — ver Notas

### Ítem de UX detectado, no arreglado

- [ ] En el overlay ⌘K hay 8 filas idénticas "Doom" porque la fila de khinsider solo muestra `platform · year` y varias comparten metadata. Distinguirlas requiere mostrar algo más (source URL, album type)

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] Drag-and-drop tracks/álbumes → playlist: probar end-to-end en macOS y web (el fix del gesture conflict en `DetailTrackRow` de la sesión previa sigue sin confirmar en runtime)
- [ ] Auditar si `LibraryView.swift`/`PlaylistsView.swift` tienen el mismo patrón de `DragGesture` a nivel de row que compite con `.onDrag`
- [ ] `TopView.swift` y `web/src/routes/top/` — archivos nuevos sin commitear, sin contexto de propósito/estado
- [ ] ID3 tags reales (TIT2/TALB/APIC)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider**
- [ ] **Mini-covers en Browse/catalog search**
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos
- [ ] Decidir si se arma DNS local (Pi-hole/dnsmasq) para acceso por dominio `.lab` en LAN

## Notas

### El working tree tiene mucho más de lo que tocó esta sesión

`git status` lista ~40 archivos modificados, incluyendo casi todo `web/src/lib/components/` y `web/src/routes/`, más `web/src/lib/stores/theme.ts` (nuevo) y `web/src/app.css`. **Esta sesión no tocó nada de web.** Esos cambios vienen de trabajo previo sin commitear (aparentemente un theme switcher). Antes de commitear, revisar ese diff aparte — no meter todo en un commit.

Archivos que **sí** tocó esta sesión:
```
VGRadio/Sources/VGRadio/Services/PlayerService.swift
VGRadio/Sources/VGRadio/Views/AlbumDetailView.swift
VGRadio/Sources/VGRadio/Views/LibraryView.swift
VGRadio/Sources/VGRadio/Views/PlayerBarView.swift
VGRadio/Sources/VGRadio/Views/SearchOverlay.swift
backend/internal/store/catalog.go
```

### Backend corre como servicio launchd

No es `go run`. Corre desde `backend/bin/vgradio-server` bajo `gui/$(id -u)/com.vgradio.server`. Para aplicar cambios de backend:

```bash
cd backend && ./update.sh   # go build -o bin/vgradio-server + launchctl kickstart -k
```

`update.sh` es untracked — commitearlo.

### Toolchain Xcode en disco externo

`DEVELOPER_DIR` apunta a `/Volumes/ExtDevDisk/Xcode.app/Contents/Developer`. CommandLineTools solo (sin ese disco montado) NO puede linkear ni el manifest de `swift build`. Esta sesión compiló sin necesitar el override explícito.

### Infraestructura homelab (sin cambios esta sesión)

| Servicio        | Host          | Acceso                                  |
|-----------------|---------------|------------------------------------------|
| Gitea           | 192.168.0.103 | http://192.168.0.103:3000                |
| Drone CI        | 192.168.0.103 | https://drone.lab                        |
| Registry        | 192.168.0.103 | 192.168.0.103:5000 (HTTP)                |
| Traefik         | 192.168.0.104 | —                                         |
| VGRadio web     | 192.168.0.104 | https://vgradio.lab · http://192.168.0.104:8085 |
| VGRadio API     | 192.168.0.104 | https://vgradio-api.lab · http://192.168.0.104:8086 |

**Drone token:** `ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4`

### Comandos útiles

```bash
# Backend: rebuild + restart del servicio
cd backend && ./update.sh

# Inspeccionar catálogo directo en SQLite
sqlite3 backend/data/vgradio.db "SELECT title, platform, year FROM catalog_entries WHERE title LIKE '%doom%' LIMIT 25;"

# Probar el endpoint de búsqueda
curl -s "http://localhost:8080/catalog?q=doom&limit=40" | python3 -m json.tool | head -40

# Build + deploy macOS (ver skill build-mac)
cd VGRadio && swift build -c release
pkill -x VGRadio; cp VGRadio/.build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app

# Web dev (svelte-check antes de dar por bueno un cambio)
cd web && npx svelte-check --tsconfig ./tsconfig.json
```
