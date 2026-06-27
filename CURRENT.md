# CURRENT — VGRadio

Última sesión: 2026-06-25

## Estado general

**Homelab deploy completo y funcional.** VGRadio corre en `https://vgradio.lab` con CI/CD automático vía Gitea + Drone. Auth, albums, favoritos — todo funcionando.

## Completado esta sesión

- [x] **Drone CI/CD end-to-end** — build #9 success: test → backend image → web image → deploy SSH
- [x] **Gitea repo activado** — `maaya/vgradio-app`, `maaya` promovido a admin en Drone (SQLite directo), repo marcado `trusted=true`
- [x] **Secret `ssh_private_key`** — agregado vía Drone API con clave `~/.ssh/drone_ci` del servidor
- [x] **Registry corregido** — `192.168.0.103:5000` (no hostname, puerto 5000)
- [x] **Deploy target correcto** — `192.168.0.104` (donde vive Traefik, no `.103`)
- [x] **Dominio API** — `vgradio-api.lab` (no `api.vgradio.lab` — cert `*.lab` no cubre segundo nivel)
- [x] **Migración de datos** — 39 albums + 1903 tracks + audio copiados al volumen Docker en `.104`
- [x] **Fix WAL conflict** — `vgradio.db-wal` del DB vacío eliminado; 39 albums OK
- [x] **Cookie cross-origin** — `SameSite=None; Secure=true` para que la sesión funcione entre `vgradio.lab` y `vgradio-api.lab`
- [x] **Favoritos funcionando** en homelab
- [x] **DEPLOY.md** — guía reutilizable para nuevos proyectos en homelab
- [x] **`scripts/migrate-to-homelab.sh`** — script para migraciones futuras
- [x] **Fix auto-scroll Album view** — `onChange` → `onAppear`: scroll a track actual solo al abrir, no en cada cambio de pista (impedía scrollear manualmente)

## Pendiente (próximos pasos inmediatos)

- [ ] **Filtro Library en web** — paridad con macOS (barra de búsqueda en `/library`, Ctrl+F)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync` para poblar búsqueda
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **origin push pendiente** — `main` adelantado 1 commit respecto a `origin/main` (GitHub/Vercel)

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
