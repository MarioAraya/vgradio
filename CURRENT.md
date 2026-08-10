# CURRENT — VGRadio

Última sesión: 2026-08-09

## En progreso

Nada a medias. El tema claro quedó implementado y compilando en ambos clientes, pero **sin verificación visual** — ver Pendiente.

`main` está **4 commits adelante de `origin/main`** y sin pushear a `gitea`. Lo único sin commitear es este `CURRENT.md` y `features.json`.

## Completado esta sesión

### Tema claro verde conmutable (light / dark / auto) — commit `6ef170b`

Web y macOS, con selector en Settings. Default sigue siendo **dark**, así que las instalaciones existentes no cambian hasta que el usuario elija.

**Web (`web/src/`)**
- [x] `app.css` — paleta dark existente intacta en `:root`; bloque `[data-theme='light']` con acento verde `#2F8F4E` y fondos `#F2F6F2`/`#FFFFFF`; bloque `[data-theme='auto']` que hereda light y vuelve a dark bajo `@media (prefers-color-scheme: dark)`
- [x] Tokens nuevos para lo que estaba hardcodeado: `--hover`, `--hover-md`, `--hover-hi`, `--scrim`, `--shadow`, `--on-accent`, `--green`, `--accent-hi`. Sustituidos ~80 literales (`rgba(255,255,255,x)`, `#131320` sobre acento, `#4caf50`, `rgba(203,168,39,x)`) en 20 archivos
- [x] `lib/stores/theme.ts` + script inline en `app.html` que aplica `data-theme` **antes del primer paint** (sin flash de paleta equivocada). Persiste en `localStorage` bajo `vgradio.theme`
- [x] `routes/settings/+page.svelte` — sección "Apariencia" con 3 botones
- [x] `npm run check` → 0 errores (18 warnings a11y preexistentes); `npm run build` OK

**macOS (`VGRadio/Sources/VGRadio/`)**
- [x] `App/DesignSystem.swift` — los `Color.vg*` pasan de constantes fijas a `NSColor(name:)` dinámicos que resuelven contra `appearance.bestMatch(from: [.aqua, .darkAqua])`. Tokens nuevos: `vgHover`, `vgHoverMd`, `vgHoverHi`, `vgAccentHi`, `vgOnAccent`. Añadido `NSColor(hex:)`
- [x] `App/ThemeStore.swift` (nuevo) — `@Observable`, persiste en `UserDefaults` (`vgradio.theme`), aplica `NSApp.appearance` (`auto` = `nil`)
- [x] `Views/SettingsView.swift` — `Picker` segmentado "APARIENCIA"
- [x] 33 `Color.white.opacity(...)` → tokens; `Color.vgBg` sobre fills de acento → `vgOnAccent`; botón play del PlayerBar `Color.white` → `Color.vgText` (era invisible en light)
- [x] `swift build` limpio

### Commits del trabajo previo que estaba sin commitear — commit `e6ddaf2`

- [x] **Top 12 por plataforma**: `GET /catalog/top12?platform=<id>`, scraper de la caja "Top 12 [Platform] Albums", caché de 6h por plataforma, mapa de slugs para 10 consolas. Vistas `TopView.swift` y `web/src/routes/top/`
- [x] **Drag & drop a playlists**: `PlaylistDragItem.swift` (macOS) + `web/src/lib/dnd.ts`, drop targets en el sidebar de ambos clientes
- [x] `backend/update.sh` versionado
- [x] Verificado antes de commitear: `go build ./...` y `swift build` OK

### Fixes de navegación, media keys y búsqueda — commits `79ee273` + `8b22e12`

Los cuatro **confirmados en runtime por el usuario**.

**Navegación de álbum rota (⌘K sin efecto + Back de dos clicks) — un solo bug**

`AlbumDetailView` no tenía identidad estable por álbum: SwiftUI reusaba la instancia al cambiar de álbum y `.task { await load() }` no volvía a correr. Abrir un álbum desde el overlay ⌘K estando ya en otro parecía no hacer nada, y Back necesitaba dos clicks (el primero caía en el álbum previo sin que la pantalla cambiara).

- [x] `LibraryView.swift` — `.id(album.id)` sobre `AlbumDetailView`
- [x] `AlbumDetailView.swift` — `.task(id: summary.id)` en vez de `.task`
- [x] `AlbumDetailView.swift` — eliminado `keyboardShortcut("k", .command)`, que secuestraba ⌘K para el buscador de tracks y tapaba el overlay global. ⌘F sigue enfocando el buscador de tracks

**Media keys tomaban Spotify (pausado) en vez de VGRadio (sonando)** — `PlayerService.swift`

- [x] `playCommand`/`pauseCommand` ya no devuelven `.commandFailed` ante desajuste de estado: eso cuesta prioridad como app Now Playing
- [x] Comandos no implementados deshabilitados explícitamente (skip/seek fwd-bwd, repeat, shuffle, rating, like, dislike, bookmark, language). Estaban enabled por default sin handler
- [x] `changePlaybackPositionCommand.isEnabled = true` — tenía handler pero nunca se habilitó
- [x] Metadata completa: artwork (descarga del cover, cacheada por track ID en `loadArtworkIfNeeded()`), artista, `MediaType.audio`, `IsLiveStream`, `DefaultPlaybackRate`. **Esto cerró el pendiente viejo "Cover en Now Playing muestra placeholder gris"**

**Buscador ⌘K no traía "DOOM Eternal" con la query "doom"**

`q=doom` tiene **162 matches** en `catalog_entries`. El overlay pedía `limit: 8` y el backend ordenaba alfabético, así que los 8 `Doom` sueltos (3DO, Jaguar, MS-DOS ×2, GBA, Saturn, PS1, SNES) copaban todos los slots.

- [x] `SearchOverlay.swift` — `limit: 8` → `40`; alto de lista 320 → 420px
- [x] `store/catalog.go` — `ORDER BY` rankea por relevancia antes que alfabético: título exacto → prefijo → inicio de palabra → resto. Sin esto, aun con limit 40 los `Doom (1993)...` copaban los primeros puestos
- [x] Verificado por curl contra el backend real

**Thumbs Down en el player bar**

- [x] `PlayerBarView.swift` — botón junto a la estrella: oculta el track (`HiddenTracksStore`) y salta al siguiente. `PlayerService.isSkippable` ya filtraba ocultos. Segundo click des-oculta sin saltar. Equivale al atajo ⌘⌫ que ya existía

**`.gitignore`** — `/backend/*.log` cubre los logs del servicio launchd

## Pendiente (próximos pasos inmediatos)

- [ ] **Push**: `main` tiene 4 commits locales. Usar el skill `/deploy` (empuja a `origin` + `gitea` a la vez)
- [ ] **Verificar el tema claro visualmente** en ambos clientes. No se hizo: el MCP de browser se desconectó a mitad de sesión. Mirar en particular:
  - Lightbox de portadas y tarjetas sobre arte de álbum (`CoverLightbox`, `CoverImage`, `CoverCarousel`, `CompactAlbumCard`) — se dejaron **a propósito** con overlays claros fijos porque van sobre arte oscuro
  - Modo `auto` cambiando el tema del sistema con la app abierta
- [ ] Drag-and-drop tracks/álbumes → playlist: probar end-to-end en macOS y web (sigue sin confirmación en runtime)
- [ ] Auditar si `LibraryView.swift`/`PlaylistsView.swift` tienen el patrón de `DragGesture` a nivel de row que compite con `.onDrag`

### Ítem de UX detectado, no arreglado

- [ ] En el overlay ⌘K hay 8 filas idénticas "Doom" porque la fila de khinsider solo muestra `platform · year` y varias comparten metadata. Distinguirlas requiere mostrar algo más (source URL, album type)

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] ID3 tags reales (TIT2/TALB/APIC)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider**
- [ ] **Mini-covers en Browse/catalog search**
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos
- [ ] Decidir si se arma DNS local (Pi-hole/dnsmasq) para acceso por dominio `.lab` en LAN
- [ ] `AddURLView`: el `TextField` no recibe foco al abrir el modal (las teclas van al terminal). `NSApp.activate` no lo resolvió

## Notas

### Decisiones de diseño del tema

- **Default dark, no auto.** Se eligió preservar el aspecto actual: quien no toque Settings no ve ningún cambio.
- **Verde solo en light.** El dark conserva el dorado `#CBA827`. Fue decisión explícita del usuario frente a "verde en ambos temas".
- **Los overlays sobre arte no se tokenizaron.** Lightbox, carrusel de portadas, píldora de play sobre la portada y el tooltip de `CompactAlbumCard` mantienen valores claros fijos: van sobre imagen oscura en cualquier tema.
- **macOS usa `NSApp.appearance`, no `.preferredColorScheme`**, para que también cambien la barra de título y los controles nativos.

### Separar hunks propios de trabajo ajeno sin commitear (pasó dos veces hoy)

`git add -i` / `-p` no funcionan en este entorno (no interactivo). Dos caminos que sí sirvieron:

1. **Filtrar hunks con `git apply --cached`** (usado para el tema). Ojo: un patch con `@@` sin números de línea es rechazado aunque se pase `--recount`.
2. **Restaurar y re-editar** (usado para los fixes de navegación, más simple cuando son pocos hunks): copiar el archivo del working tree a un backup, `git checkout HEAD -- archivo`, aplicar solo los cambios propios sobre la versión de HEAD, `git add`, y devolver el backup al working tree. El índice queda con lo propio y el árbol intacto.

### `git checkout` de rama con archivos modificados en común

Al mergear la rama de los fixes, `git checkout main` falló porque los archivos tocados tenían cambios sin commitear que chocaban. Solución sin tocar el árbol: verificar con `git merge-base --is-ancestor main <rama>` y mover la etiqueta con `git branch -f main <rama>`. El `checkout` posterior no modifica nada porque ambos apuntan al mismo commit.

### `.gitignore` no soporta comentarios inline

`/backend/*.log   # comentario` no ignora nada — el patrón queda literal con el comentario incluido. El comentario va en su propia línea. La regla preexistente `/backend/data/   # cache: SQLite...` tiene el mismo defecto; funciona de casualidad por las reglas explícitas de `backend/data/*.db` de más abajo.

### El working tree venía con dos sesiones de trabajo mezcladas

Al empezar había ~35 archivos modificados de trabajo previo (Top 12, drag & drop) sobre los que se aplicó el tema. Para commitear el tema por separado hubo que **filtrar hunks por regex** y aplicarlos con `git apply --cached`, porque `git add -i`/`-p` no funcionan en este entorno (no interactivo). Los scripts quedaron en el scratchpad de la sesión, no en el repo. Si vuelve a pasar, ese es el camino: generar el diff, quedarse con los hunks cuyas líneas `+`/`-` sean todas del tema **y** estén balanceadas (sustituciones puras), y aplicar al índice.

### Backend corre como servicio launchd

No es `go run`. Corre desde `backend/bin/vgradio-server` bajo `gui/$(id -u)/com.vgradio.server`. Para aplicar cambios de backend:

```bash
cd backend && ./update.sh   # go build -o bin/vgradio-server + launchctl kickstart -k
```

### Toolchain Xcode en disco externo

`DEVELOPER_DIR` apunta a `/Volumes/ExtDevDisk/Xcode.app/Contents/Developer`. CommandLineTools solo (sin ese disco montado) NO puede linkear ni el manifest de `swift build`.

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

# Probar el endpoint Top 12
curl -s "http://localhost:8080/catalog/top12?platform=ps1" | python3 -m json.tool

# Build + deploy macOS (ver skill build-mac)
cd VGRadio && swift build -c release
pkill -x VGRadio; cp VGRadio/.build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app

# Web: chequeo de tipos y build
cd web && npm run check && npm run build
```
