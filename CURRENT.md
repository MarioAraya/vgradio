# CURRENT — VGRadio

Última sesión: 2026-06-14

## En progreso

### Rama `users` — refactor favoritos + SearchModal (uncommitted)

Cambios sin commitear que mejoran la arquitectura de favoritos y añaden búsqueda global.

**Qué hay sin commitear:**

1. **`trackFavorites.ts`** (nuevo) — store centralizado `Set<number>` de IDs favoritos. Reemplaza tracking por componente. `initTrackFavorites()` carga desde API al login.
2. **`SearchModal.svelte`** (nuevo) — modal de búsqueda global, activa con `Cmd+K` / `Ctrl+K`.
3. **`authModal.ts` fix** — `requireAuth()` ahora verifica si user ya está logueado antes de abrir modal (bug: antes siempre abría el modal).
4. **`PlayerBar.svelte`** — favoritos usan `favoritedTrackIDs` Set en vez del store `favorites` viejo.
5. **`+layout.svelte`** — añade `<SearchModal>`, atajo `Cmd+K`, llama `initTrackFavorites()` tras `initAuth()`.
6. **`albums/[id]/+page.svelte`** — usa `favoritedTrackIDs` Set; catalog number es ahora link a `vgmdb.net/search?q=<catalog>`.
7. **`browse/+page.svelte`** — post-import muestra link clickeable al álbum (en vez de solo ✓); `imported` record guarda `albumId` string.
8. **`favorites/+page.svelte`** — llama `setTrackFavorited(id, false)` al unfavoritar.

**Decisiones tomadas:**
- Catalog number → link de búsqueda en vgmdb.net (opción 1: búsqueda, no link directo). VGMdb no tiene URL directa por catalog number; usa IDs numéricos internos.
- `trackFavorites` es un `Set<number>` global en vez de array, para O(1) lookup en listas largas.

**Preguntas pendientes:**
1. ¿`SearchModal` ya tiene lógica de búsqueda implementada o solo es el shell visual?

## Completado esta sesión (antes del trabajo sin commitear)

- [x] **Spotify-style player bar + fullscreen** (`bacc002`) — UX polish, controles mejorados
- [x] **CORS fix** (`c77afba`) — reflect Origin header en vez de env var fija
- [x] **Multi-user auth frontend** (`6641da3`) — lazy login, favorites, user menu
- [x] **Multi-user auth backend** (`945000c`) — sessions, favorites, enrichment endpoints

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear rama `users`** — los 8 archivos modificados/nuevos están listos para commit
- [ ] **Verificar SearchModal** — confirmar que tiene funcionalidad de búsqueda o implementarla
- [ ] **Re-sync letra S** — con fix del seen-map, S debería traer ~12k álbumes (antes: ~22/409 por página)
- [ ] **Merge `users` → `main`** — cuando esté todo verificado
- [ ] **Deploy VPS** — backend + frontend
- [ ] **FTS5 para búsqueda** — `LIKE '%q%'` full scan, con >50k entries puede ser lento
- [ ] **Tests backend Go** — cero tests actualmente

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
# Stats backend
curl -s http://localhost:8080/stats

# Web dev
cd /Users/maaya/dev/vgradio-app/web && npm run dev

# Sync letra S
curl -X POST http://localhost:8080/catalog/sync?letter=S
```
