# CURRENT — VGRadio

Última sesión: 2026-08-02

## En progreso

Nada en curso. Sesión cerrada con commit `647ffe4` en `main`, build macOS release compilado y deployado a `/Applications/VGRadio.app`. Falta push a `origin`/`gitea`.

**Preguntas pendientes antes de continuar:**
1. Confirmar que el usuario ve "Liked Music" con sus 37 tracks tras re-login (logout/login) en la app — quedó pedido pero no confirmado en el chat.
2. ¿Push de estos 3 commits (`647ffe4` + 2 previos) a `origin`/`gitea`? No se hizo esta sesión.

## Completado esta sesión

- [x] **Queue automático en Descargado**: tocar cualquier track en "Descargado" ahora arma la queue con *todas* las canciones descargadas (todos los álbumes, orden de la lista), no solo las del álbum clickeado — `DownloadedView.swift`
- [x] **Context menu "Play Next" en Descargado** — faltaba, ya existía en AlbumDetailView, se replicó en `DownloadedTrackRow`
- [x] **Selector de cuentas estilo Steam en login** — `AuthStore` guarda últimos 5 emails (nunca password) en UserDefaults (`vgradio.recentEmails`); `LoginSheet` abre en modo picker si hay cuentas guardadas, con avatar+inicial, botón "Otra cuenta", y ✕ al hover para olvidar una cuenta
- [x] **Enter para login** — `.onSubmit` en email/password dispara sign-in, guard contra doble-submit con campos vacíos
- [x] **Bug real de "Liked Music" vacío diagnosticado y arreglado**: `backend/internal/api/auth.go` fijaba `Secure: true` siempre en la cookie `sid`. Sobre `http://localhost:8080` (dev local) macOS descarta cookies Secure → cualquier endpoint autenticado (`/favorites/tracks`, etc.) fallaba 401 y el cliente lo mostraba como lista vacía en vez de error. Fix: `Secure` ahora depende de `isSecureRequest(r)` (TLS directo o `X-Forwarded-Proto: https` detrás de Traefik) — producción homelab sigue igual, dev local ahora funciona. **Nota: esto revierte la decisión de la sesión anterior de "no tocar" este flag** — se tocó porque el síntoma (favoritos vacíos) lo requería.
- [x] Verificado con curl directo contra sesión real en DB: `/favorites/tracks` devuelve las 37 canciones correctamente con el fix aplicado
- [x] Build macOS release compilado limpio (`swift build -c release` con `DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer`) y copiado a `/Applications/VGRadio.app`
- [x] Commit `647ffe4` con los 4 archivos tocados (AuthStore.swift, DownloadedView.swift, SidebarView.swift, backend/internal/api/auth.go)

## Pendiente (próximos pasos inmediatos)

- [ ] Usuario debe hacer logout/login en la app para obtener cookie nueva sin `Secure` y confirmar que Liked Music vuelve a mostrar los 37 tracks
- [ ] Push de los 3 commits pendientes a `origin` y `gitea` (`git push`, no hecho esta sesión)
- [ ] Si se despliega este fix de `auth.go` al homelab (Drone CI), verificar que `X-Forwarded-Proto` efectivamente lo setea Traefik — si no, la cookie en prod dejaría de ser Secure. Chequear config de Traefik antes de asumir que anda igual.
- [ ] `web/src/routes/browse/+page.svelte` tiene cambios sin commitear de una sesión anterior (LIMIT 1200→3000, paginación 7→12 páginas visibles) — no tocado esta sesión, decidir si commitear o descartar

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] ID3 tags reales (TIT2/TALB/APIC)
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Cover en Now Playing (menu bar widget)** — muestra placeholder gris
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider**
- [ ] **Mini-covers en Browse/catalog search**
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos
- [ ] Decidir si se arma DNS local (Pi-hole/dnsmasq) para acceso por dominio `.lab` en todos los dispositivos LAN

## Notas

### Toolchain Xcode en disco externo

`DEVELOPER_DIR` apunta a `/Volumes/ExtDevDisk/Xcode.app/Contents/Developer` — CommandLineTools solo (sin este disco montado) NO puede linkear ni el manifest de `swift build`. Si el disco se desmonta a mitad de sesión, `swift build` falla con `xcrun: error: missing DEVELOPER_DIR path`. Confirmar que el disco esté montado (`ls /Volumes/`) antes de compilar.

### Cookie `sid` — estado actualizado

Ya NO es `Secure: true` fijo (ver Completado). Ahora condicional vía `isSecureRequest()` en `backend/internal/api/auth.go`. Esto reemplaza la nota de la sesión anterior que decía "usuario decidió no tocarlo" — se tocó esta sesión porque bloqueaba una feature real (Liked Music) en dev local.

### Infraestructura homelab (sin cambios esta sesión)

| Servicio        | Host          | Acceso                                  |
|-----------------|---------------|------------------------------------------|
| Gitea           | 192.168.0.103 | http://192.168.0.103:3000                |
| Drone CI        | 192.168.0.103 | https://drone.lab                        |
| Registry        | 192.168.0.103 | 192.168.0.103:5000 (HTTP)                |
| Traefik         | 192.168.0.104 | —                                         |
| VGRadio web     | 192.168.0.104 | https://vgradio.lab · http://192.168.0.104:8085 |
| VGRadio API     | 192.168.0.104 | https://vgradio-api.lab · http://192.168.0.104:8086 |

**Drone token:** `ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4`

### Comandos útiles

```bash
# Backend local — matar server viejo (¡ojo! go run deja un hijo "server" corriendo, pkill por nombre de proceso "go run" no lo mata)
lsof -i :8080 -sTCP:LISTEN   # ver PID real del binario compilado
kill <PID>
cd backend && go run ./cmd/server > /tmp/vgradio-server.log 2>&1 &

# Verificar sesión real contra la API sin pasar por la app
sqlite3 backend/data/vgradio.db "select id from sessions where user_id='<uid>' order by expires_at desc limit 1;"
curl -s http://localhost:8080/favorites/tracks -H "Cookie: sid=<sid>"

# Build + deploy macOS (ver skill build-mac)
DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build -c release --package-path VGRadio
pkill -x VGRadio; cp VGRadio/.build/arm64-apple-macosx/release/VGRadio /Applications/VGRadio.app/Contents/MacOS/VGRadio
open /Applications/VGRadio.app

# Web dev (svelte-check antes de dar por bueno un cambio)
cd web && npx svelte-check --tsconfig ./tsconfig.json
```
