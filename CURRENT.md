# CURRENT — VGRadio

Última sesión: 2026-06-25

## En progreso

### Verificar app en homelab

Pipeline CI/CD completo y corriendo. Backend + web desplegados en `192.168.0.104`. DB migrada (39 albums, 1903 tracks). Falta confirmar que el browser accede correctamente a `https://vgradio.lab`.

**Pendiente confirmar:**
- `mkcert -install` en Mac (CA ya instalado según output, pero Chrome da `ERR_CERT_COMMON_NAME_INVALID` — posible cache)
- Agregar a `/etc/hosts`: `192.168.0.104  vgradio.lab vgradio-api.lab` (ya está `vgradio-api.lab` renombrado a `vgradio-api.lab`)
- Login con `arayaromero@gmail.com` en `https://vgradio.lab`

**Decisiones tomadas:**
- API en `vgradio-api.lab` (no `api.vgradio.lab`) — cert `*.lab` no cubre segundo nivel
- Registry en `192.168.0.103:5000` (IP directa, no hostname)
- Deploy target: `192.168.0.104` (donde está Traefik), build en `192.168.0.103` (donde está Drone/Gitea)
- `docker cp` / `docker run alpine` para escribir al volumen sin sudo

## Completado esta sesión

- [x] **Drone CI/CD funcional** — build #8 success: backend-test → backend-image → web-image → deploy (todos ✅)
- [x] **Repo Gitea activado y trusted** — `maaya` promovido a admin en Drone DB para poder marcar repo trusted (necesario para `extra_hosts`)
- [x] **Secret `ssh_private_key` en Drone** — agregado vía API usando token de DB SQLite
- [x] **Deploy path corregido** — `/srv/vgradio` → `~/srv/vgradio` (sin sudo passwordless)
- [x] **Registry corregido** — `registry.lab` → `192.168.0.103:5000` (puerto 5000, no 80)
- [x] **Deploy a host correcto** — `192.168.0.103` → `192.168.0.104` (donde vive Traefik)
- [x] **`traefik-net` creada en `.104`** — ya existía, solo faltaba verificar
- [x] **Dominio renombrado** — `api.vgradio.lab` → `vgradio-api.lab` (wildcard `*.lab` cubre solo un nivel)
- [x] **Migración de datos** — 39 albums + 1903 tracks + archivos de audio copiados al volumen Docker en `.104`
- [x] **WAL conflict resuelto** — `vgradio.db-wal` del DB vacío eliminado; backend sirve 39 albums
- [x] **DEPLOY.md creado** — guía completa para nuevos proyectos en homelab
- [x] **`scripts/migrate-to-homelab.sh`** — script reutilizable para migraciones futuras

## Pendiente (próximos pasos inmediatos)

- [ ] **Verificar `https://vgradio.lab` en browser** — agregar a `/etc/hosts` y confirmar TLS OK
- [ ] **Login en homelab** — `arayaromero@gmail.com` con contraseña del backend local
- [ ] **Filtro Library en web** — paridad con macOS (barra de búsqueda en `/library`)
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas abajo)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Sincronizar catalog en homelab** — `POST /catalog/sync` para poblar la tabla de búsqueda

## Notas

### Infraestructura homelab

| Servicio    | Host            | URL                              |
|-------------|-----------------|----------------------------------|
| Gitea       | 192.168.0.103   | http://192.168.0.103:3000        |
| Drone CI    | 192.168.0.103   | https://drone.lab                |
| Registry    | 192.168.0.103   | 192.168.0.103:5000 (HTTP)        |
| Traefik     | 192.168.0.104   | 192.168.0.104:8888 (dashboard)   |
| VGRadio web | 192.168.0.104   | https://vgradio.lab              |
| VGRadio API | 192.168.0.104   | https://vgradio-api.lab          |

**Drone token** (para API): `ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4`  
Obtener con: `sqlite3 /var/lib/docker/volumes/cicd_drone_data/_data/database.sqlite "SELECT user_login, user_hash FROM users;"`  
(copiar DB local primero: `docker cp drone:/data/database.sqlite /tmp/drone.sqlite`)

### `/etc/hosts` local (Mac) — entradas necesarias

```
192.168.0.104  vgradio.lab vgradio-api.lab
```

Agregar con: `sudo sh -c 'echo "192.168.0.104  vgradio.lab vgradio-api.lab" >> /etc/hosts'`

### CF clearance para Einhander

Tracks 3+ de EINHÄNDER ORIGINAL SOUNDTRACK fallan (mp3_url vacío, khinsider 404 sin CF cookie).

```bash
# 1. Obtener cf_clearance del browser (DevTools → Application → Cookies → downloads.khinsider.com)
# 2. Setear en backend homelab:
curl -X PUT https://vgradio-api.lab/config/cf-clearance \
  -H 'Content-Type: application/json' \
  -d '{"value":"CF_COOKIE_AQUI"}'
# 3. Re-scrape:
curl -X POST https://vgradio-api.lab/albums/9ee1fa540f28534f/scrape-tracks
```

### Comandos útiles

```bash
# Retrigger build en Drone
curl -sk -X POST "https://drone.lab/api/repos/maaya/vgradio-app/builds/<N>" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4"

# Ver logs de build
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds/<N>/logs/1/<step>" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4"

# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd /Users/maaya/dev/vgradio-app/backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Build macOS app
cd /Users/maaya/dev/vgradio-app/VGRadio && swift build -c release
pkill -x VGRadio 2>/dev/null; sleep 0.3
cp .build/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app

# Migración de datos (si se necesita re-migrar)
bash scripts/migrate-to-homelab.sh
```
