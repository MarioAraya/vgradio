# CURRENT — VGRadio

Última sesión: 2026-06-14

## Completado esta sesión

- [x] **Settings page** (`b23d9ff`) — Backend URL editable + test conexión, lista álbumes descargados con tamaño en disco + eliminar local, stats de biblioteca + scrape all pending
- [x] **4 endpoints backend** (`b23d9ff`) — `GET /stats`, `GET /albums/downloaded`, `DELETE /albums/{id}/local`, `POST /scrape/pending`
- [x] **Per-letter catalog sync** (`e163af5`) — `POST /catalog/sync?letter=S`, botón "Sync X" en Browse cuando hay letra seleccionada
- [x] **cf_clearance propagado al Syncer** (`e163af5`) — `PUT /config/cf-clearance` actualiza fetcher Y syncer. Campo en Settings para pegarlo.
- [x] **Fix crítico scraper** (`e163af5`) — `extractCatalogEntries` en `scraper/catalog.go`: icon links (sin texto) envenenaban el `seen` map antes de checar `title == ""`, bloqueando title links. Solo 22/409 álbumes por página. Fix: checar title primero, luego seen.
- [x] **Entries live en sync progress** (`e163af5`) — counter de entries se actualiza por página, no solo al final
- [x] **Merge web → main** (`07d4ec0`) — branch `web` mergeado, ahora en `main`

---

## Estado actual

- **Rama:** `main`
- **Backend:** corriendo en :8080 (verificar con `lsof -i :8080`)
- **Catalog:** ~13477 entries (S + X + otros syncs anteriores, pre-fix)
- **Biblioteca:** 12 álbumes, 598 tracks, 138 scrapeados, 460 pendientes

---

## Pendiente (próximos pasos inmediatos)

- [ ] **Re-sync letra S** — el fix del seen-map cambia completamente cuántos álbumes se trae. Con el fix, S debería traer ~12070 de una sola página (Browse → S → Sync "S"). Los 13477 actuales son mezcla de syncs viejos (parciales) + X.
- [ ] **FTS5 para búsqueda** — `LIKE '%q%'` full scan. Con >50k entries puede volverse lento. Migrar a SQLite FTS5 virtual table.
- [ ] **Deploy VPS** — backend + frontend
- [ ] **Tests backend Go** — cero tests actualmente
- [ ] **Push a Gitea** — `git push gitea main`

---

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
El código de paginación que implementamos existe pero nunca se activa (page 2 devuelve 0).
El fix del seen-map era el problema real: 22/409 ≈ 5% de álbumes por página.

### cf_clearance — actualmente innecesaria

khinsider no está desafiando con CF (sin cookie y curl funciona). Si vuelve a bloquear:
- Abrir khinsider.com en browser
- DevTools → Application → Cookies → `downloads.khinsider.com`
- Copiar valor de `cf_clearance`
- Settings → pegar → Guardar

### Comandos útiles

```bash
# Stats
curl -s http://localhost:8080/stats
curl -s "http://localhost:8080/catalog?limit=1" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'], 'entries')"

# Sync letra S manualmente
curl -X POST http://localhost:8080/catalog/sync?letter=S

# Web dev
cd /Users/maaya/dev/vgradio-app/web && npm run dev
```
