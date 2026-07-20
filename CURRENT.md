# CURRENT — VGRadio

Última sesión: 2026-07-20

## En progreso

### Renombrado legible de archivos offline (macOS)

Feature pedida: los mp3 descargados offline se guardaban como `<trackId>.mp3` (ej. `279.mp3`), ilegible en Finder. Usuario eligió explícitamente la opción "renombrar" (no ID3 tags — más riesgo/complejidad, descartado por ahora).

**Contexto recopilado:**
- `DownloadedTrack` (Models.swift) ya tenía toda la metadata necesaria (`albumTitle`, `name`) para construir un nombre legible — solo faltaba el campo para el nombre de archivo real.
- El folder offline es un security-scoped bookmark (`NSOpenPanel` + `bookmarkData`) — cualquier operación de FileManager sobre él (incl. la migración) necesita `startAccessingSecurityScopedResource()`, ya se sigue ese patrón en `downloadOffline`.

**Decisiones tomadas (implementadas):**
- `DownloadedTrack.fileName: String?` nuevo (opcional, así no rompe el decode de entradas JSON viejas que no lo tenían). `resolvedFileName` computed hace fallback a `"<id>.mp3"` si `fileName` es nil.
- Nuevo naming: `"{Album} - {Track}.mp3"`, sanitizado (sin `/` ni `:`, cap 80 chars), con dedupe por sufijo `(2)`, `(3)`... si ya existe ese nombre.
- Migración automática al arrancar (`migrateLegacyFileNames()` en `OfflineStore.init()`): renombra en disco los archivos legacy `<id>.mp3` a la nueva convención, una sola vez. Se salta las entradas placeholder `"Descargas antiguas"` (del migrate anterior de formato `[String]` → `[DownloadedTrack]`, sin metadata real de track/álbum) — esas se quedan con el nombre legacy porque no hay info útil para un nombre mejor.
- Todos los sitios que antes derivaban la ruta con `"\(id).mp3"` (`localURL`, `offlineStorageBytes`, `offlineStorageBytes(albumID:)`) ahora usan `track.resolvedFileName`.

**Preguntas pendientes antes de continuar:**
1. Ninguna bloqueante. Falta: build+run interactivo para confirmar que la migración renombra bien los archivos ya descargados hoy (el usuario mostró captura con `279.mp3`, `280.mp3`, etc. — verificar que al abrir la app esos pasan a `"Álbum - Track.mp3"`).

## Completado esta sesión

Sesión larga, múltiples rondas de fixes/features. En orden:

- [x] **Offline downloads "Descargado"**: `OfflineStore.swift` reescrito con metadata completa, `DownloadedView.swift` nueva, badges track/álbum descargado, item sidebar
- [x] Fix perf: Library scrolleaba con jank — swipe-back monitor escribía a `@State` en cada evento de scroll vertical, ahora usa un tracker de referencia (no dispara render) y solo promueve a `@State` en gesto horizontal confirmado
- [x] Fix: filas del sidebar solo clickeables sobre el texto — `HStack+Spacer` no forzaba ancho completo
- [x] Fix: header de tabla de tracks desalineado (columnas ⬇/☁️ se excluían condicionalmente en vez de reservar espacio fijo)
- [x] "Visit source" agregado en macOS (ya existía en web), tenue-visible en ambos (antes invisible-hasta-hover en web)
- [x] Botón "descargar álbum completo" (offline) en macOS — álbum y también en playlists (Liked Music + playlists normales)
- [x] Cover-download-as-ZIP movido a ícono hover-only dentro de la portada (antes botón standalone) — web + macOS
- [x] Cmd+K como shortcut alternativo para filtrar tracks dentro de un álbum (además de Cmd+F)
- [x] Cover/título en Favorites/Descargado/Liked Music ahora navegan al álbum completo (macOS) — web ya lo tenía
- [x] **Recently Played implementado de cero** — era un stub permanente vacío, nunca se grababa nada. `PlayerService` ahora hace `POST /history` en cada track (endpoint que ya existía en backend, nadie lo llamaba), `RecentlyPlayedView.swift` nueva con fetch real
- [x] **Settings convertido a página del sidebar** (antes modal) — agregada sección "Álbumes descargados" con lista + tamaño + botón Eliminar por álbum (pedido explícito: no había forma de ver/liberar espacio offline)
- [x] Quitado del sidebar macOS: Top 40, Favorites (duplicaba Liked Music), Add URL de Quick Actions (sigue con Cmd+5) — archivos huérfanos borrados (`Top40View.swift`, `FavoritesView.swift`)
- [x] Quitado "Wishlist" del sidebar web (ruta/store se dejaron intactos)
- [x] Tercer modo de vista Library "Compact" (macOS + web): covers tamaño grid normal, gap casi 0, sin epígrafe — con tooltip custom instantáneo (~80ms, sin librería externa) mostrando título/plataforma/año/duración/favorito
- [x] Fix bug visual: filas de tracks se veían "apagadas" aunque estuvieran descargadas offline — el brillo dependía solo de la caché de servidor (⬇), no del offline (☁️)
- [x] Quitado botón "Add to Queue" (▶+) de header y filas de track — sigue accesible por click derecho → "Play Next"
- [x] Ícono header "👁" (eye, no coincidía con el ícono real) → "👎" (thumbsdown, coincide con `hand.thumbsdown`)
- [x] Fix bug: `Text("\(year)")` en SwiftUI aplica agrupación de miles por locale (gotcha de `LocalizedStringKey`) → "1.993" en vez de "1993". Arreglado en 4 sitios (wrap con `String(year)`). Web no tenía el bug (interpolación JS plana)
- [x] **Wishlist eliminado por completo del cliente macOS** (sección Library + `WishlistStore.swift` + botón bookmark en Browse) — botón "Add" de Browse ahora importa directo a la library
- [x] **Header sidebar macOS** = "☰ VGRadio" (hamburger colapsa sidebar, igual Cmd+B), sacada la barra de búsqueda duplicada con Cmd+K, filas de menú más grandes (15pt/38pt)
- [x] "Library" title en macOS ahora muestra "N albums" al lado, matching web
- [x] **Web: filtro "Filter albums…" con Cmd+F** + Escape limpia, y los mismos 3 modos de vista que macOS (persistidos en localStorage)
- [x] Botón "Abrir en Finder" para la carpeta offline en Settings
- [x] Nombres de archivo legibles para descargas offline: `"Álbum - Track.mp3"` + migración automática de nombres legacy

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear el último cambio** — sin commitear: `Models.swift` (campo `fileName`), `OfflineStore.swift` (renombrado + migración)
- [ ] **Probar interactivamente** la migración de nombres de archivo (abrir app, verificar en Finder que los `279.mp3` etc pasaron a nombre legible)
- [ ] **Push pendiente** — verificar cuántos commits adelante de `origin/main`
- [ ] ID3 tags reales (TIT2/TALB/APIC) — usuario lo descartó esta sesión por riesgo/complejidad, pero quedó mencionado como posible follow-up si más adelante lo quiere
- [ ] Resto de pendientes de sesiones anteriores sigue igual (ver abajo)

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] **Filtro Library en web** — ✅ ya resuelto esta sesión (Cmd+F + filtro), tachar de sesiones futuras
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Cover en Now Playing (menu bar widget)** — muestra placeholder gris
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider** — ver detalle en notas técnicas abajo
- [ ] **Mini-covers en Browse/catalog search** — ver detalle en notas técnicas abajo
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos

## Notas

### Build macOS requiere SSD externo montado

Xcode vive en `/Volumes/ExtDevDisk/Xcode.app` (CommandLineTools solo no compila). El SSD se desmontó varias veces durante esta sesión sin aviso — siempre verificar con `ls /Volumes/ExtDevDisk/Xcode.app/Contents/Developer` antes de compilar; si falla, pedirle al usuario que reconecte el disco.

```bash
cd VGRadio && DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build -c release
pkill -x VGRadio 2>/dev/null; sleep 0.3
cp .build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app
```

### Gotcha SwiftUI: Text con interpolación de números

`Text("\(someInt)")` (interpolación de string) usa `LocalizedStringKey` internamente, que SÍ aplica separador de miles según el locale del sistema — incluso dentro de interpolación literal, no solo con `Text(someInt)` directo. Para evitar esto, siempre `Text("\(String(someInt))")` o pre-convertir a `String` antes de armar el string interpolado. Mordió en year (1993 → "1.993") en varios lugares esta sesión.

### Arquitectura offline (macOS-only)

Favoritos, Descargado (offline), Recently Played y "álbum completo download" son conceptos exclusivos de macOS — no hay backend ni tablas SQL para favoritos-offline (favoritos normales sí son backend). Web no tiene ningún concepto de "offline files", solo streaming. Si en algún momento se quiere paridad, requeriría diseño nuevo de sync cross-device (mencionado en `features.json` v2 roadmap: `favorites-backend`, pero offline-per-device es otra cosa).

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
# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Web dev (svelte-check antes de dar por bueno un cambio)
cd web && npx svelte-check --tsconfig ./tsconfig.json

# Ver build Drone
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds?limit=3" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4" | python3 -m json.tool
```
