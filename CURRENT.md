# CURRENT — VGRadio

Última sesión: 2026-07-23

## En progreso

Nada en curso — todo commiteado y pusheado a `gitea` (Drone dispara build/deploy en homelab). Pendiente: confirmar visualmente el resultado (no había browser MCP conectado durante buena parte de esta sesión, todo se validó por código + `svelte-check`).

**Preguntas pendientes antes de continuar:**
1. ¿Login/favoritos por IP:puerto se necesitan de verdad, o alcanza con catálogo+reproducción sin sesión? (cookie `sid` tiene `Secure:true` hardcodeado, no se tocó — ver Notas)
2. ¿Seguir con DNS local (Pi-hole/dnsmasq) para que TV/celular resuelvan `*.lab` sin exponer puertos? Quedó como opción discutida, no implementada.

## Completado esta sesión

- [x] **Fix estrella favorito invisible en álbum (web)** — vivía dentro de `.acts` (opacity:0 hasta hover). Extraída a `.fav-btn` propio en `albums/[id]/+page.svelte`, siempre visible cuando el track está en favoritos (commit `5e98786`)
- [x] **PlayerBar fullscreen (web)**:
  - Click fuera del cover/controles cierra el overlay (`on:click|self`, mismo patrón que `CoverLightbox.svelte`)
  - Cover agrandado: `240px` fijo → `min(400px, 60vw)`
  - Botones favorito (★) y thumbs-down (👎) agregados al transport de fullscreen
  - Ícono play/pause agrandado (bar normal 16px→20px, fullscreen 20px→26px)
- [x] **Thumbs-down en bottom bar principal** — nuevo botón a la derecha de Repeat, oculto por defecto (`opacity:0`), visible solo en hover de `.player-bar`; si el track está oculto (marcado) queda siempre visible en dorado
  (commit `22a1143`, junto con lo de abajo)
- [x] **Puertos fijos de dev en `docker-compose.yml`** — `web` expuesto en `192.168.0.104:8085`, `backend` en `:8086`, bypass de Traefik para que dispositivos LAN sin `/etc/hosts` (smart TV, celular) puedan acceder directo por IP
- [x] Deploy: push a `gitea` → Drone CI dispara build en homelab (commits `5e98786` y `22a1143`)

## Pendiente (próximos pasos inmediatos)

- [ ] **Verificar visualmente en browser real** los 3 cambios de esta sesión (estrella álbum, fullscreen player, iconos agrandados) — no se pudo probar con browser MCP en buena parte de esta sesión
- [ ] **Confirmar en la TV** que `http://192.168.0.104:8085` carga catálogo/reproducción tras el deploy de Drone
- [ ] Decidir si se arma DNS local (Pi-hole/dnsmasq) para acceso por dominio `.lab` en todos los dispositivos LAN (discutido, no implementado)
- [ ] Si se quiere login/favoritos desde IP:puerto plano: cambiar `Secure:true` → condicional en `backend/internal/api/auth.go:58` (usuario decidió **no** tocarlo esta sesión por riesgo, queda descartado salvo que lo pida de nuevo)

### Pendientes de sesiones anteriores (sin tocar esta sesión)

- [ ] ID3 tags reales (TIT2/TALB/APIC) — descartado sesión anterior, posible follow-up
- [ ] **Sincronizar catalog en homelab** — `POST https://vgradio-api.lab/catalog/sync`
- [ ] **Einhander tracks 3+** — necesita CF clearance (ver notas)
- [ ] **Mega Man: The Power Battle** — no está en DB, agregar vía Add URL
- [ ] **Cover en Now Playing (menu bar widget)** — muestra placeholder gris
- [ ] **feat: scrapear por año/consola/todo el catálogo khinsider**
- [ ] **Mini-covers en Browse/catalog search**
- [ ] **Cert mkcert roto para subdominios `.lab`** — wildcard `*.lab` estructuralmente inválido, requiere regenerar con SANs explícitos

## Notas

### Cookie `sid` y acceso por IP:puerto plano

`backend/internal/api/auth.go:58` fija `Secure: true` + `SameSite: None` en la cookie de sesión. Sobre HTTP plano (sin TLS) el browser nunca la guarda → login/favoritos no funcionan accediendo por `192.168.0.104:8086` directo. Catálogo y reproducción sí funcionan (no requieren sesión). CORS del backend (`router.go:190-203`) ya refleja cualquier origin, no es el bloqueante — es puramente el flag `Secure`. Usuario decidió no tocar esto esta sesión.

### `.env.production` del frontend está stale/sin uso

`web/.env.production` tiene `VITE_API_URL=https://api.vgradio.lab` (dominio que NO existe — el real es `vgradio-api.lab`, ver `.drone.yml:46`). No es un bug activo: el build real de CI usa el valor correcto vía `.drone.yml`, este `.env.production` no se lee en el pipeline. Podría confundir a futuro si alguien corre `vite build` local sin pasar el env var explícito.

### Infraestructura homelab (actualizado)

| Servicio        | Host          | Acceso                                  |
|-----------------|---------------|------------------------------------------|
| Gitea           | 192.168.0.103 | http://192.168.0.103:3000                |
| Drone CI        | 192.168.0.103 | https://drone.lab                        |
| Registry        | 192.168.0.103 | 192.168.0.103:5000 (HTTP)                |
| Traefik         | 192.168.0.104 | —                                         |
| VGRadio web     | 192.168.0.104 | https://vgradio.lab · **http://192.168.0.104:8085** (nuevo, sin login) |
| VGRadio API     | 192.168.0.104 | https://vgradio-api.lab · **http://192.168.0.104:8086** (nuevo, sin login) |

**Drone token:** `ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4`

### Router ISP (VTR/Claro, cable no fibra)

Para DNS local (`*.lab`) hace falta admin del router. Clave suele venir en sticker del equipo; si no, soporte técnico la da por teléfono. Riesgo: routers de cable VTR/Claro suelen venir bloqueados sin opción de DNS custom — salida típica es poner router propio en modo bridge/AP detrás del del ISP.

### Comandos útiles

```bash
# Backend local
kill $(lsof -t -i :8080) 2>/dev/null; sleep 1
cd backend && go run ./cmd/server > /tmp/vgradio.log 2>&1 &

# Web dev (svelte-check antes de dar por bueno un cambio)
cd web && npx svelte-check --tsconfig ./tsconfig.json

# Ver build Drone
curl -sk "https://drone.lab/api/repos/maaya/vgradio-app/builds?limit=3" \
  -H "Authorization: Bearer ZBnZ9g6QuAZDp3GUzDyL6H2NwSU63oT4" | python3 -m json.tool
```
