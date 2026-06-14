# CURRENT — VGRadio

Última sesión: 2026-06-13

## Sin commitear (listo para commit)

1 archivo modificado:
- `backend/internal/fetcher/fetcher.go` — eliminado override de HTTP/1.1 forzado; ahora usa `http.DefaultClient` que soporta HTTP/2 automáticamente

---

## Completado esta sesión

- [x] **3 estados visuales por track** (`e8e1c1a`) — dot verde (local), dot amarillo (scraped), botón `🔗` (sin scrape)
- [x] **Scrape batch + individual** (`e8e1c1a`) — `POST /albums/{id}/scrape-tracks` + botón por track
- [x] **Fix khinsider double-encoding** (`e8e1c1a`) — `absURL()` hace PathUnescape, 576 rows DB corregidos
- [x] **Fix fetcher HTTP/2** (sin commit) — `vgradio-s` antiguo tenía transport HTTP/1.1 forzado que rompía con CF/h2; removido → `http.DefaultClient` negocia h2 correctamente
- [x] **Verificado funcionando** — `curl http://localhost:8080/tracks/214/resolve` retorna URL correcta

---

## Pendiente (próximos pasos inmediatos)

- [ ] **Commitear fetcher fix** — `backend/internal/fetcher/fetcher.go`
- [ ] **Push a Gitea** — `git push gitea web`
- [ ] **Verificar tracks 7-10 Dracula Battle** en web y macOS app
- [ ] **Recently played view** — sidebar link existe, vista stub vacía
- [ ] **Settings view** — backend URL configurable desde UI
- [ ] **Deploy VPS**
- [ ] **Tests backend Go**

---

## Notas

### Fix HTTP/2 en fetcher (importante para ops)

El backend compilado anterior (`vgradio-s`) tenía el transport con `TLSNextProto = {}` que deshabilitaba H2. CF/khinsider negocia H2 via ALPN y responde con frames H2, lo que causaba `malformed HTTP response \x00\x00\x12\x04...`.

Fix: usar `http.DefaultClient` (nil Transport → http.DefaultTransport que incluye soporte H2 nativo de Go).

**Diagnóstico futuro si reaparece:**
1. Verificar qué proceso corre en :8080 → `lsof -i :8080`
2. Si es `vgradio-s` en vez del `go run` → el binary viejo sigue corriendo → `kill <PID>` y reiniciar

### Matar el backend correctamente

```bash
kill $(lsof -t -i :8080)
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &
```
`pkill -f vgradio` NO funciona porque el binary compilado se llama `vgradio-s`.

### Comandos

- Backend: `cd backend && go run ./cmd/server` (puerto 8080)
- Web dev: `cd web && npm run dev` (puerto 5173)
- Logs: `tail -f /tmp/vgradio.log`
- Push: `git push gitea web`

### LAN

- Frontend usa `window.location.hostname:8080`
- F5 mata el audio — limitación browser
