# CURRENT — VGRadio

Última sesión: 2026-07-05

## En progreso

### Fixes UI macOS: área de click en Sidebar + doble-click en Favorites

**Contexto recopilado:**
- Bug 1: en `SidebarView.swift` solo el texto/icono de cada row respondía al click, no toda el área (ancho/alto). Causa: SwiftUI no cuenta como tappable un fondo `Color.clear` — falta `.contentShape(Rectangle())`.
- Bug 2: en `FavoritesView.swift`, `FavoriteTrackRow` no tenía ningún gesto de doble-click — solo el botón "Play all" reproducía. Patrón correcto ya existía en `AlbumDetailView.swift` (`DetailTrackRow` + `.onTapGesture(count: 2)`).
- Toolchain: `xcode-select` apuntaba a CommandLineTools (sin SDK completo) → build fallaba con símbolos de `PackageDescription` no encontrados. Se resolvió apuntando a `/Volumes/ExtDevDisk/Xcode.app/Contents/Developer` (disco externo debe estar montado).

**Decisiones tomadas (implementadas):**
- `.contentShape(Rectangle())` agregado en todos los rows/botones de `SidebarView.swift`: Library/Browse/Favorites/Recently Played, Liked Music, playlists, New playlist, Add URL, Sign in.
- `FavoriteTrackRow` ahora recibe `group` (tupla del álbum) para armar el queue completo al hacer doble-click, igual que `AlbumDetailView`.

**Preguntas pendientes antes de continuar:**
1. Ninguna — falta solo probar interactivamente en la app corriendo (ver Pendiente).

## Completado esta sesión

- [x] Fix área de click en `SidebarView.swift` (todo el row, no solo el texto)
- [x] Fix doble-click en `FavoritesView.swift` → reproduce track + arma queue del álbum
- [x] Build release compila limpio (`swift build -c release`), sin warnings nuevos
- [x] Resuelto `xcode-select` apuntando a Xcode.app del disco externo (ya no requiere `DEVELOPER_DIR=` manual)

## Pendiente (próximos pasos inmediatos)

- [ ] **Copiar binario nuevo al `.app` bundle** (dock apunta a `/Applications/VGRadio.app`, desactualizado del 24 jun):
  ```bash
  pkill -x VGRadio 2>/dev/null; sleep 0.3
  cp /Users/maaya/dev/vgradio-app/VGRadio/.build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
  open /Applications/VGRadio.app
  ```
- [ ] **Probar interactivamente**: click en cualquier parte de los textos del sidebar, doble-click en un track de Favorites
- [ ] **Commitear cambios** si prueba OK — `VGRadio/Sources/VGRadio/Views/{FavoritesView,SidebarView}.swift` sin commitear
- [ ] **Filtro Library en web** — paridad con macOS (barra de búsqueda en `/library`, Ctrl+F)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync` para poblar búsqueda
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL

## Notas

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
# Build macOS
cd VGRadio && swift build -c release
pkill -x VGRadio 2>/dev/null; sleep 0.3
cp .build/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app

# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Ver build Drone
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds?limit=3" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4" | python3 -m json.tool
```
