# CURRENT — VGRadio

Última sesión: 2026-06-14

## Completado esta sesión

- [x] **Settings page** (`b23d9ff`) — 3 secciones: Conexión (backend URL + test), Álbumes descargados (lista + eliminar local), Biblioteca (stats + scrape all pending)
- [x] **4 nuevos endpoints backend** (`b23d9ff`) — `GET /stats`, `GET /albums/downloaded`, `DELETE /albums/{id}/local`, `POST /scrape/pending`
- [x] **Settings → cf_clearance** — campo en Settings para pegar cookie CF y enviarla al backend (fetcher + syncer)
- [x] **Per-letter catalog sync** (`e163af5`) — `StartLetter(ctx, letter)` en Syncer + `POST /catalog/sync?letter=S` + botón "Sync S" en Browse
- [x] **Fix crítico scraper** (`e163af5`) — `extractCatalogEntries` marcaba URLs como vistas antes de checar si el link tenía texto; icon links (sin texto) "envenenaban" el seen-map, bloqueando los title links → solo 22/409 álbumes scrapeados por página. Fix: checar `title == ""` antes de marcar seen.
- [x] **Catalog entries live count** durante sync — `entries` en progress ahora se actualiza por página, no solo al final
- [x] **cf_clearance propagado al Syncer** — `PUT /config/cf-clearance` ahora llama a `syncer.SetCFClearance()` además de `fetcher.SetCFClearance()`

---

## Estado actual

- **Backend:** corriendo en :8080
- **Catalog:** 13477 entries (sync S + X corridos con fix)
- **Biblioteca:** 12 álbumes, 598 tracks, 138 scrapeados, 460 pendientes
- **Browse sin `cf_clearance`:** funciona igual, khinsider no desafió con CF (no hay cookie)

---

## Pendiente (próximos pasos)

- [ ] **Verificar sync S completo** — después del fix del seen-map, S debería traer ~12070. Actualmente hay ~13477 totales (S+X+otros de antes). Correr Sync S desde Browse para completar.
- [ ] **FTS5 para búsqueda** — `LIKE '%q%'` hace full scan. Con >50k entries puede volverse lento. Migrar a SQLite FTS5.
- [ ] **Favoritar desde album detail** — ya existe (★/☆ por track), confirmado en sesión
- [ ] **Deploy VPS** — backend + frontend
- [ ] **Tests backend Go** — cero tests actualmente
- [ ] **Push a Gitea** — `git push gitea web`

---

## Notas

### Fix kill backend correcto

`pkill -f "go run.*server"` mata solo el orquestador, el binary hijo sigue en :8080.

```bash
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1; cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &
```

### Sync de letras khinsider

- Browse pages NO están paginadas — todos los álbumes de una letra están en una sola página
- La paginación `?page=N` que implementamos no se usa (no hay page 2, devuelve 0)
- El bug del seen-map era el problema real: 22 de 409 ≈ 5% de álbumes scrapeados
- Sin `cf_clearance`: funciona (khinsider no está desafiando actualmente)
- Con `cf_clearance`: Settings → pega valor de DevTools → khinsider.com → Application → Cookies

### Comandos útiles

```bash
# Backend
kill $(lsof -t -i :8080) 2>/dev/null && go run ./cmd/server > /tmp/vgradio.log 2>&1 &
tail -f /tmp/vgradio.log

# Stats
curl -s http://localhost:8080/stats
curl -s "http://localhost:8080/catalog?limit=1" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'], 'entries')"

# Web dev
cd web && npm run dev
```

### Favoritos ya implementados

★/☆ por track en album detail + "Favorite all" en header. No había nada que agregar.
