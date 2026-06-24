# CURRENT — VGRadio

Última sesión: 2026-06-24

## En progreso

### CF clearance para resolver MP3 URLs de Einhander

Tracks 3+ de EINHÄNDER ORIGINAL SOUNDTRACK fallan al reproducir. Causa: `mp3_url` vacío en DB y khinsider retorna HTTP 404 al intentar resolver (Cloudflare bloquea sin `cf_clearance`). Tracks 1-2 funcionan porque ya tenían `mp3_url` cacheado de scrape anterior.

**Estado DB (album_id = `9ee1fa540f28534f`):**
- Tracks 1-2: `mp3_url` = `https://nu.vgmtreasurechest.com/...` ✅
- Tracks 3+: `mp3_url` vacío, `page_url` = `https://downloads.khinsider.com/...%231...` → 404

**Pasos para resolver:**
1. Obtener `cf_clearance` de khinsider (browser → DevTools → Application → Cookies, o Playwright CLI)
2. `curl -X PUT http://localhost:8080/config/cf-clearance -d '{"value":"COOKIE_VALUE"}'`
3. `curl -X POST http://localhost:8080/albums/9ee1fa540f28534f/scrape-tracks`

**Notas CF clearance:**
- Se puede set en runtime vía `PUT /config/cf-clearance` o via `VGRADIO_CF_CLEARANCE` env var al iniciar server
- CF clearance cookies tienen TTL corto (~1h), necesitan renovarse
- `cloudscraper` Python o Playwright Node son las opciones CLI para obtenerla sin abrir browser manualmente

## Completado esta sesión

- [x] **Favorites sincronizados entre macOS y web** — `FavoritesStore.swift` reescrito: elimina `UserDefaults`, ahora usa `GET /favorites/tracks` + `POST /favorites/tracks/{id}`. Updates optimistas en local state. `ContentView` llama `favorites.load()` en `onAppear` y al cambiar `auth.currentUser`.
- [x] **APIClient: métodos de track favorites** — `favoriteTracks()` y `toggleTrackFavorite(id:)` agregados a `APIClient.swift`.
- [x] **Tuple `grouped` con `albumId`** — `FavoritesStore.grouped` ahora expone `albumId` en el tuple. Tipos en `FavoriteGroupView` y `LikedMusicGroupView` actualizados. Build limpio.
- [x] **Diagnóstico Einhander** — confirmado que el problema es `mp3_url` vacío + khinsider 404 sin CF clearance. No es bug de código.

## Pendiente (próximos pasos inmediatos)

- [ ] **Resolver Einhander tracks 3+** — necesita CF clearance válido. Ver pasos en "En progreso" arriba.
- [ ] **Mega Man: The Power Battle** — álbum no está en DB. Agregar vía Add URL con URL de khinsider.
- [ ] **Confirmar Rockman importa** — pendiente de sesión anterior (fix URL doble)
- [ ] **Commitear esta sesión** — varios archivos modificados sin commitear (FavoritesStore, APIClient, ContentView, FavoritesView, PlaylistsView + archivos de sesión anterior)
- [ ] **Filtro Library en web** — paridad con macOS (Ctrl+F o barra de búsqueda en `/library`)
- [ ] **Merge `users` → `main`** — rama 2 commits adelante de origin
- [ ] **Deploy VPS** — backend + frontend

## Notas

### Por qué Einhander tracks 1-2 sí suenan y 3+ no

Tracks 1-2 tienen `mp3_url` cacheado (CDN `nu.vgmtreasurechest.com`) de un scrape anterior con CF válido.
Tracks 3+ tienen nombre con `#` (p.ej. `Stage1 #1-`). Sus `page_url` en khinsider incluyen `%23` (encoding correcto),
pero al intentar resolver ahora sin `cf_clearance`, khinsider retorna 404. El `#` no es el bug — es la ausencia de CF cookie.

### Favorites: arquitectura antes vs después

**Antes:** `FavoritesStore` → `UserDefaults` (local, no sincronizado entre plataformas)
**Ahora:** `FavoritesStore` → `GET/POST /favorites/tracks` (DB, sincronizado web↔macOS)
Web ya usaba la API desde antes (trackFavorites.ts). El localStorage `favorites.ts` es código legacy en web — no lo usa "Liked Music".

### Binary de producción: siempre reemplazar /Applications/VGRadio.app

```bash
swift build -c release
pkill -x VGRadio 2>/dev/null; sleep 0.3
cp .build/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app
```

La app corre desde `/Applications/VGRadio.app/Contents/MacOS/VGRadio`, NO desde el binary SPM directamente.

### Cómo matar y reiniciar backend correctamente

```bash
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd /Users/maaya/dev/vgradio-app/backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &
tail -f /tmp/vgradio.log
```

`pkill -f "go run.*server"` NO funciona — mata el orquestador pero el binary hijo sigue en :8080.

### sourceUrl en catalog = URL absoluta

`GET /catalog` devuelve `sourceUrl` como URL completa. No agregar base URL al usarla.

### Comandos útiles

```bash
# Tests backend
cd /Users/maaya/dev/vgradio-app/backend && go test ./...

# Build macOS
cd /Users/maaya/dev/vgradio-app/VGRadio && swift build -c release

# Web dev
cd /Users/maaya/dev/vgradio-app/web && npm run dev

# Stats backend
curl -s http://localhost:8080/stats

# Set CF clearance en runtime
curl -X PUT http://localhost:8080/config/cf-clearance -H 'Content-Type: application/json' -d '{"value":"CF_COOKIE_AQUI"}'

# Re-scrape tracks de un álbum (tras renovar CF)
curl -X POST http://localhost:8080/albums/9ee1fa540f28534f/scrape-tracks
```
