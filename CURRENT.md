# CURRENT — VGRadio

Última sesión: 2026-07-05

## En progreso

### Búsqueda multi-palabra (token match) + Cmd+F en Browse + limpieza warning build

**Contexto recopilado:**
- Búsqueda anterior era substring simple (`contains(query)`) — falla con "rockman forte" contra "Rockman & Forte FC" si el orden/puntuación no calza exacto.
- Se agregó `matchesSearchQuery(haystack, query)` en `Models.swift`: parte el query por espacios y exige que cada palabra aparezca en el haystack (orden libre, case-insensitive).
- Aplicado en `LibraryView.swift` (título+plataforma) y `SearchOverlay.swift` (título+plataforma).
- `BrowseView.swift` ahora tiene `Cmd+F` para foco en su search field (`@FocusState searchFocused`), igual patrón que `AlbumDetailView`.
- Backend (`catalog.go`, `SearchCatalog`/`CountCatalog`): antes un solo `LIKE '%q%'`; ahora itera `strings.Fields(q)` y agrega un `LIKE` por palabra — mismo espíritu multi-token pero server-side, para `/catalog`.
- Warning de build resuelto: `AlbumDetailView.swift:517` — `await MainActor.run { ... }` con retorno de `NSWorkspace.shared.selectFile` (Bool) sin usar. Fix: `_ = await MainActor.run { ... }` (dos ocurrencias, líneas 351 y 517-518, ambas iguales — mismo patrón de descarga de covers ZIP).

**Decisiones tomadas (implementadas):**
- Un solo helper `matchesSearchQuery` en `Models.swift`, reusado por Library/SearchOverlay (evita duplicar lógica de tokenización).
- Backend usa `LIKE` por palabra en vez de regex/FTS — simple, consistente con lo ya existente.

**Preguntas pendientes antes de continuar:**
1. Ninguna bloqueante — falta probar build+run interactivo y decidir si commitear junto o separar macOS/backend.

## Completado esta sesión

- [x] `matchesSearchQuery` en `Models.swift` (búsqueda tokenizada)
- [x] `LibraryView.swift` y `SearchOverlay.swift` usan el nuevo matcher
- [x] `BrowseView.swift`: Cmd+F enfoca el campo de búsqueda
- [x] `catalog.go`: `SearchCatalog`/`CountCatalog` con `LIKE` multi-palabra
- [x] Fix warning `MainActor.run` result unused en `AlbumDetailView.swift` (líneas 351 y 517)
- [x] `./scripts/build-mac.sh` corrió OK, warning limpio confirmado por usuario

## Pendiente (próximos pasos inmediatos)

- [ ] **Probar interactivamente**: búsqueda multi-palabra en Library, SearchOverlay y Browse (Cmd+F debe enfocar)
- [ ] **Commitear cambios** — sin commitear: `Models.swift`, `AlbumDetailView.swift`, `BrowseView.swift`, `LibraryView.swift`, `SearchOverlay.swift`, `backend/internal/store/catalog.go`
- [ ] **Push pendiente** — rama `main` está 6 commits adelante de `origin/main`, sin pushear
- [ ] **Filtro Library en web** — paridad con macOS (barra de búsqueda en `/library`, Ctrl+F) — sigue pendiente de sesión anterior
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync` para poblar búsqueda
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Cover en Now Playing (notification center widget)** — popup de la barra de menú (ícono ▶ en menu bar) muestra placeholder gris en vez del cover del álbum
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider** — 3 modos: (1) endpoint para escrapear por consola (ya existe letra/consola parcial, revisar `catalog/syncer.go`), (2) por año (`/game-soundtracks/year/2026`), (3) full catalog (`/game-soundtracks`, 102971 álbumes, 206 páginas). Necesita: ir a la letra del álbum o buscarlo por Cmd+K en Library, o sección "por descargar/scrapear" (similar a wishlist) para trackear qué falta bajar.
- [ ] **Mini-covers en Browse/catalog search** — `/catalog` (Browse macOS+web) es texto solo. `CatalogEntry` (`backend/internal/scraper/catalog.go:14`) no tiene campo cover — el scraper de browse/console pages (`extractCatalogEntries`) nunca capturó thumb URL, solo el album detail page trae covers. Para paridad visual con búsqueda original de khinsider (grid con mini-cover + título + plataforma/tipo/año): agregar `CoverThumbURL` a `CatalogEntry`, parsear `<img>` thumb en `extractCatalogEntries`, columna nueva en tabla `catalog`, actualizar `SearchCatalog`/`CountCatalog`, y grid UI en Browse (macOS/web).

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
# Build macOS (usar el script, no manual)
./scripts/build-mac.sh

# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Ver build Drone
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds?limit=3" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4" | python3 -m json.tool
```
