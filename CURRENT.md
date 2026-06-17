# CURRENT — VGRadio

Última sesión: 2026-06-16

## En progreso

### macOS app UX polish (sin commitear)

Varios refinamientos de UI/UX en la app macOS. Cambios sin commitear:

**Archivos modificados:**
- `DesignSystem.swift` — sidebar 220→180px, playerBar 72→56px
- `PlayerBarView.swift` — layout 3-columnas (cover+info LEFT | transport CENTER | vol+acciones RIGHT)
- `ContentView.swift` — Cmd+B toggle sidebar, Space key via `NSEvent.addLocalMonitorForEvents` (reemplaza `.onKeyPress` que no funcionaba bien), toolbar oculto, ignoresSafeArea top
- `SidebarView.swift` — padding top 12→36 (espacio para titlebar sin toolbar), `maxWidth: .infinity`, ignoresSafeArea top
- `PlayerService.swift` — `isEnabled = true` en remote commands, `playbackState` explícito en NowPlayingInfoCenter
- `AlbumDetailView.swift` — botón "hide track" también llama `player.next()` si es el track actual
- `web/src/routes/albums/[id]/+page.svelte` — misma lógica hide+skip en web

**Decisiones tomadas:**
- `.toolbar(.hidden, for: .windowToolbar)` para quitar barra de título nativa y dar estilo borderless
- Space key con `NSEvent.addLocalMonitorForEvents` en lugar de `.onKeyPress` porque `.onKeyPress` solo funciona si la vista tiene foco de teclado
- PlayerBar a 3 columnas con `Color.clear + .overlay` para centrado real del transport

**Preguntas pendientes:**
1. ¿Compilar y verificar en Xcode antes de commitear? (Cambios no testeados en build real)
2. ¿SearchModal tiene búsqueda implementada o solo es shell visual?

## Completado esta sesión

- [x] **macOS UX polish** — sidebar más angosta, player bar más compacta, layout 3-col, Cmd+B toggle sidebar, Space key fix, hide-track skip-if-current (Swift + Svelte)
- [x] **NowPlayingInfo fix** — `playbackState` explícito + `isEnabled` en remote commands

## Completado sesiones anteriores

- [x] **Tests backend Go** — 29/29 pasan (`go test ./...`, ~8.7s)
- [x] `61098e0` — favorites centralizados (`trackFavorites.ts`), SearchModal (`Cmd+K`), UX improvements
- [x] `bacc002` — Spotify-style player bar + fullscreen
- [x] `c77afba` — CORS fix (reflect Origin header)
- [x] `6641da3` — frontend multi-user auth (lazy login, favorites, user menu)
- [x] `945000c` — backend multi-user auth (sessions, favorites, enrichment)

## Pendiente (próximos pasos inmediatos)

- [ ] **Compilar y verificar** — abrir Xcode, build, probar Cmd+B, Space, player bar layout
- [ ] **Commitear UX polish** — si build pasa, un commit limpio con todos los cambios Swift + Svelte
- [ ] **Verificar SearchModal** — ¿tiene funcionalidad de búsqueda o solo shell visual?
- [ ] **Merge `users` → `main`** — rama limpia, tests pasan, lista para merge
- [ ] **Deploy VPS** — backend + frontend
- [ ] **Re-sync letra S** — con fix del seen-map, S debería traer ~12k álbumes
- [ ] **FTS5 para búsqueda** — `LIKE '%q%'` full scan, con >50k entries puede ser lento

## Notas

### Cómo matar y reiniciar backend correctamente

```bash
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd /Users/maaya/dev/vgradio-app/backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &
tail -f /tmp/vgradio.log
```

`pkill -f "go run.*server"` NO funciona — mata el orquestador pero el binary hijo sigue en :8080.

### Browse pages khinsider — NO están paginadas

Todos los álbumes de una letra están en una sola URL (`/browse/S`). No hay `?page=2`.
El fix del seen-map era el problema real: 22/409 ≈ 5% de álbumes por página.

### cf_clearance — actualmente innecesaria

khinsider no está desafiando con CF. Si vuelve a bloquear:
- DevTools → Application → Cookies → `downloads.khinsider.com` → copiar `cf_clearance`
- Settings → pegar → Guardar

### VGMdb — no hay URL directa por catalog number

Solo existe búsqueda: `https://vgmdb.net/search?q=CATALOG`. Las páginas de álbum usan IDs numéricos (`vgmdb.net/album/12345`). Para links directos habría que enriquecer la DB con IDs de vgmdb (opción futura).

### Comandos útiles

```bash
# Tests backend
cd /Users/maaya/dev/vgradio-app/backend && go test ./...

# Stats backend
curl -s http://localhost:8080/stats

# Web dev
cd /Users/maaya/dev/vgradio-app/web && npm run dev

# Sync letra S
curl -X POST http://localhost:8080/catalog/sync?letter=S
```
