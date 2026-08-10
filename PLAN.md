# PLAN — VGRadio Connect (control remoto entre instancias)

> Objetivo: como Spotify Connect. Varias instancias (macOS app, web, tv) logueadas con la
> misma cuenta se ven entre sí, muestran qué está sonando y pueden controlar / robar la
> reproducción de la instancia activa.
>
> Estado: diseño. No implementado. Pensado para ejecutarse en una sesión aparte.

---

## 0. Contexto actual (verificado en el repo)

| Pieza | Dónde | Nota |
|---|---|---|
| Backend | `backend/` Go 1.26, stdlib `net/http` + SQLite (`modernc.org/sqlite`) | sin deps de websocket |
| Auth | cookie `sid`, `authMiddleware` en `backend/internal/api/middleware.go` | renueva sesión en cada request |
| Router | `backend/internal/api/router.go` | `NewRouter(s, q, f, syn, dataDir, log)`, CORS refleja Origin con credentials |
| Player web | `web/src/lib/stores/player.ts` | `queue: QueueItem[]` con `{track, album, covers}` por ítem |
| Player macOS | `VGRadio/Sources/VGRadio/Services/PlayerService.swift` | `queue: [Track]` + `currentAlbum` + `currentCovers` globales |
| Cliente HTTP macOS | `VGRadio/Sources/VGRadio/Services/APIClient.swift` | `URLSession` con `HTTPCookieStorage.shared` |

Divergencia relevante: el modelo de cola **no es el mismo** en web y macOS. El protocolo
tiene que definir un formato de cable propio y que cada cliente lo hidrate a su modelo.

---

## 1. Modelo conceptual

Tres conceptos, uno por entidad:

1. **Device** — una instancia viva de la app. Se registra al arrancar, manda heartbeat, muere por TTL.
2. **PlaybackState** — el estado de reproducción *del usuario*, no del dispositivo. Único por usuario. Lo posee el device activo.
3. **Command** — una orden que un device manda al device activo (o a otro), enrutada por el backend.

Regla de oro: **el backend no reproduce nada ni interpreta la cola**. Es un relay con estado.
La lógica de shuffle/repeat/hidden sigue viviendo en cada cliente. Esto evita reescribir los
dos players y mantiene el backend chico.

### Quién manda

- Sólo el **device activo** puede publicar `PlaybackState`. Publicaciones de otros se descartan (409).
- Cualquier device puede **mandar comandos**. El backend los enruta al activo.
- Cualquier device puede **reclamar el rol activo** (`transfer`). Es la operación que cambia dueño.

---

## 2. Protocolo

### Transporte: SSE (downlink) + POST (uplink)

**Decisión: SSE, no WebSocket.** Razones:
- Cero dependencias nuevas (`net/http` + `Flusher` alcanza). WS necesitaría `coder/websocket` o `gorilla`.
- El tráfico real es asimétrico: mucho push del servidor, pocos comandos del cliente.
- Reconexión automática en el browser (`EventSource`), y `Last-Event-ID` gratis.
- Atraviesa Traefik sin config especial.

Contra: en Swift hay que leer el stream a mano (`URLSession.bytes(for:)`), y el navegador
limita conexiones por origen en HTTP/1.1 (6). Con HTTP/2 en Traefik no aplica; en dev
(`localhost:8080`, HTTP/1.1) puede molestar con muchas pestañas — aceptable.

**Gotcha crítico:** `srv.WriteTimeout = 60s` en `backend/cmd/server/main.go:71` **mata la
conexión SSE al minuto**. Hay que poner `WriteTimeout: 0` y aplicar deadlines por handler
con `http.ResponseController`, o excluir la ruta. Sin esto el feature "funciona" pero se
cae cada 60s y parece un bug de red.

También mandar `X-Accel-Buffering: no` por si algún proxy bufferea.

### Endpoints nuevos

Todos bajo `requireAuth`. Prefijo `/connect`.

```
GET    /connect/events            SSE. Stream de eventos del usuario.
POST   /connect/devices           Registrar/renovar device. Body: {id, name, type, capabilities}
DELETE /connect/devices/{id}      Baja explícita (cierre limpio de la app)
GET    /connect/devices           Lista devices vivos del usuario
POST   /connect/state             Publicar estado. Sólo device activo. Body: PlaybackState
POST   /connect/command           Mandar comando. Body: {targetDeviceId?, type, payload}
POST   /connect/transfer          Reclamar el rol activo. Body: {deviceId, play: bool}
```

### Tipos de cable

```jsonc
// Device
{
  "id": "dev_a1b2c3",              // generado por el cliente, estable por instancia
  "name": "MacBook de Maaya",      // editable en Settings
  "type": "macos" | "web" | "tv",
  "capabilities": ["play","volume","seek","queue"],
  "isActive": true,
  "lastSeen": "2026-08-09T22:00:00Z"
}

// PlaybackState — lo publica sólo el device activo
{
  "rev": 42,                       // lo asigna el backend, monótono por usuario
  "deviceId": "dev_a1b2c3",
  "isPlaying": true,
  "positionSec": 87.5,
  "updatedAt": "2026-08-09T22:00:00Z",  // para interpolar posición en los espectadores
  "volume": 0.8,
  "isMuted": false,
  "isShuffle": false,
  "repeatMode": "off" | "all" | "one",
  "queueIndex": 3,
  "coverIndex": 0,
  "queue": [ { "trackId": "trk_001", "albumId": "alb_7f3a" } ]
}

// Command
{
  "type": "play" | "pause" | "toggle" | "next" | "prev" | "seek"
        | "volume" | "mute" | "shuffle" | "repeat"
        | "playContext" | "queueAdd" | "queueRemove" | "queueMove",
  "payload": { }                   // según type
}
```

**La cola viaja como `{trackId, albumId}`, no como objetos completos.** Un álbum de 72 tracks
con covers serializado entero son ~50 KB por update; así son ~4 KB. Cada cliente hidrata con
`GET /albums/{id}` (que ya cachea) y guarda un mapa `albumId → Album` en memoria.

`playContext` es el comando gordo: `{albumId | playlistId, startTrackId, shuffle}`. Deja que
el device activo arme la cola él mismo desde su propia fuente, en vez de mandar 72 ítems.
Es también lo que permite "reproducir esto en la otra máquina" desde la vista de álbum.

### Eventos SSE

```
event: hello        data: {deviceId, activeDeviceId, state, devices}   // snapshot inicial
event: state        data: PlaybackState                                // cambió el estado
event: devices      data: [Device]                                     // alguien entró/salió
event: command      data: {from, type, payload}                        // sólo al device destino
event: transfer     data: {activeDeviceId, state}                      // cambió el dueño
: ping                                                                  // keepalive cada 15s
```

---

## 3. Backend — diseño

### Hub en memoria

`backend/internal/connect/hub.go`. Nuevo paquete, sin dependencia del `store` salvo para
persistencia opcional.

```go
type Hub struct {
    mu    sync.RWMutex
    users map[string]*userHub   // userID → hub
}

type userHub struct {
    devices  map[string]*device   // deviceID → device
    active   string               // deviceID activo, "" si ninguno
    state    PlaybackState
    rev      int64
}

type device struct {
    meta     DeviceMeta
    ch       chan event    // buffered, cap 32
    lastSeen time.Time
}
```

Reglas de implementación:
- **Canal bufferizado + drop**: si `ch` está lleno (cliente colgado), se descarta el evento
  y se marca el device para desconexión. Nunca bloquear el `mu` escribiendo en un canal.
- **Copiar el estado bajo lock, serializar fuera del lock.**
- **Barrido de TTL**: goroutine cada 15s, expulsa devices con `lastSeen > 45s`. Si el
  expulsado era el activo → `active = ""` y se emite `devices` + `transfer` con activo vacío.
- El hub se crea en `main.go` y se inyecta al router igual que `syncer`.

### Persistencia (mínima)

Tabla nueva, sólo para "seguir donde lo dejé" tras reiniciar el backend:

```sql
CREATE TABLE IF NOT EXISTS playback_state (
    user_id     TEXT PRIMARY KEY,
    state_json  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
```

Escritura **debounced**: máximo 1 write cada 10s por usuario, más un flush en `pause` y en
shutdown. Sin esto SQLite come un write cada 500ms por cada track sonando.

Los `Device` **no se persisten**. Son efímeros por definición.

### Seguridad

- Todo `/connect/*` bajo `requireAuth`. `userID` sale del contexto, **nunca del body**.
- Un comando sólo puede apuntar a un `deviceId` que esté en el `userHub` del emisor. Si no
  está → 404 (no 403: no filtrar existencia de devices ajenos).
- Límite de devices por usuario (p.ej. 8) para que un bug de reconexión no coma memoria.
- Rate limit simple en `/connect/command` y `/connect/state` (token bucket por device,
  ~20 req/s) — el `positionSec` de un player manda mucho tráfico si algo se descontrola.

### Tests (`backend/internal/connect/hub_test.go`)

1. Registro de device → aparece en `devices` de ese usuario y no en el de otro.
2. Publicar estado desde device no activo → rechazado, `rev` no cambia.
3. `transfer` → cambia `active`, emite evento a todos los devices del usuario.
4. Comando a device de otro usuario → 404.
5. TTL expulsa device muerto y libera el rol activo.
6. Canal saturado no bloquea al resto de los suscriptores.

En `handlers_test.go`: SSE devuelve `text/event-stream`, manda `hello` y sobrevive a un
write posterior (regresión del `WriteTimeout`).

---

## 4. Clientes

### Contrato común (implementar igual en los dos)

Cada cliente tiene tres modos:

| Modo | Qué hace |
|---|---|
| **Local** | Es el device activo. Reproduce y publica `state`. Comportamiento actual. |
| **Remoto** | Otro device es el activo. No reproduce nada. La UI del player refleja el `state` recibido y los botones mandan `command`. |
| **Desconectado** | Sin SSE. Se comporta 100% como hoy (fallback total). El feature nunca debe romper la reproducción local. |

Publicación de estado desde el device activo: en cada cambio discreto (play/pause/track/
seek/volume/queue) **inmediatamente**, y además cada 5s mientras suena, para el heartbeat.
Los espectadores **interpolan** la posición localmente entre updates usando `updatedAt` —
así la barra de progreso se mueve suave sin mandar un POST por segundo.

### Web (`web/src/lib/`)

Archivos nuevos:
- `connect.ts` — cliente SSE (`EventSource`), registro de device, envío de comandos, reconexión con backoff.
- `stores/connect.ts` — store Svelte: `{devices, activeDeviceId, isRemote, remoteState}`.

Cambios en `stores/player.ts`:
- Un guard al principio de cada acción pública: si `isRemote`, en vez de tocar el `<audio>`
  se manda el comando y se retorna. El resto del store queda igual.
- Cuando `isRemote` pasa a `true`: pausar el `<audio>` local.
- Cuando llega un `command` siendo activo: ejecutarlo por el mismo camino que la UI local.

**Device ID por pestaña**: guardar en `sessionStorage`, no `localStorage` — si no, dos
pestañas comparten id y se pisan el estado. Nombre por defecto `"Navegador — <fecha>"`,
editable en Settings.

UI: botón tipo "Connect" en `PlayerBar` que abre un popover con la lista de devices, marca
el activo, y al clickear otro dispara `transfer`. Cuando `isRemote`, la barra muestra un
banner verde "Sonando en <device>" (el tema verde ya existe).

### macOS (`VGRadio/Sources/VGRadio/`)

Archivos nuevos:
- `Services/ConnectService.swift` — `@MainActor @Observable`. SSE vía
  `URLSession.shared.bytes(for:)` + parseo de líneas `event:`/`data:`. Reconexión con backoff.
- `Views/DevicePickerView.swift` — popover en `PlayerBarView`.

Cambios en `PlayerService.swift`:
- `var connect: ConnectService?` (mismo patrón que `hiddenTracks` / `offline`).
- `isRemote` → `togglePlay/next/previous/seek/volume` mandan comando en vez de tocar `AVPlayer`.
- En modo remoto **desactivar `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`**: si no,
  macOS cree que esta app está sonando y las teclas de medios se van a pelear (ya hubo un
  fix de prioridad de media keys en esta app — ver commit `79ee273`).
- Publicar estado desde el `addPeriodicTimeObserver` que ya existe, throttled a 5s.

**Device ID**: `UUID` en `UserDefaults` bajo `vgradio.deviceId`. Nombre por defecto
`Host.current().localizedName`.

**Cookie**: `APIClient` ya usa `HTTPCookieStorage.shared`; la request SSE tiene que salir por
la misma `URLSession` para llevar el `sid`.

---

## 5. Puntos que se decidieron y por qué

**Estado en el backend, no P2P.** Un mDNS/Bonjour local sería más "directo" pero no funciona
entre la web y el homelab, ni fuera de la LAN, y no hay cuenta compartida que lo autorice. El
backend ya es el punto de verdad de la sesión.

**El backend no arma la cola.** Mandar `playContext` y dejar que el device activo resuelva
tracks contra la API que ya usa evita duplicar en Go la lógica de shuffle/hidden/playlists
que existe dos veces (TS y Swift) y que además difiere por device.

**`hiddenTracks` sigue siendo local.** Es un store por dispositivo (`HiddenTracksStore`,
`stores/hidden.ts`). Consecuencia aceptada: al transferir, el nuevo device puede saltear
tracks distintos. Alternativa (migrar hidden al backend por usuario) queda fuera de scope.

**Sin OT/CRDT.** `rev` monótono + "sólo el activo escribe" alcanza. El conflicto real
(dos devices publicando a la vez) sólo existe durante el transfer, y ahí gana quien reclamó.

---

## 6. Fases

Cada fase es entregable y verificable por separado.

### Fase 0 — Refactors previos de bajo riesgo

Tres cambios que se justifican solos (arreglan bugs que existen hoy) y además quitan de
encima la parte más frágil de Connect. Van en commits separados, antes de la Fase 1.

**R1 — Quitar el `WriteTimeout` global.** `backend/cmd/server/main.go:73` corta *toda*
respuesta a los 60s. No es sólo un problema futuro del SSE: `/tracks/{id}/stream`,
`/tracks/{id}/download` y `/albums/{id}/covers.zip` ya viven bajo ese límite hoy — un MP3
grande a conexión lenta se corta. Fix: `WriteTimeout: 0` en el server + middleware
`writeDeadline` que aplica el límite con `http.ResponseController` sólo a las rutas de
respuesta corta. Requiere `Unwrap()` en `statusWriter` para que el `ResponseController`
atraviese el wrapper del logger (también necesario después para el `Flush()` del SSE).

**R2 — Unificar el modelo de cola en macOS.** Web ya lo hizo (`player.ts:17`, con el
comentario que explica por qué). macOS no, y arrastra el bug: `QueuePanel.swift:44` pasa
`player.currentAlbum?.title` a *todas* las filas, y `PlayerService.swift:103`
`playNext(_ track:)` inserta el track sin álbum — call sites cross-album en
`AlbumDetailView.swift:970` y `DownloadedView.swift:209`. Encolar un track de otro álbum
muestra cover y título equivocados. Migrar a `QueueItem { track, album, covers }` como en
web. Superficie en Views: `currentAlbum` 7 usos, `queue` 4, `currentCovers` 3,
`queueIndex` 3. Es el único de los tres que merece verificación manual.

**R3 — Punto único de mutación de estado.** Hoy web muta en 10 `update(s => …)` sueltos y
Swift asigna propiedades directas + `didSet`. Connect necesita "cada cambio → publicar";
sin punto único hay que sembrar ~15 llamadas y olvidarse de una da un device desincronizado
sólo al cambiar shuffle — caro de encontrar. Añadir `commit()` + listeners en `player.ts` y
`onStateChange` en `PlayerService`. Hook no-op: no cambia comportamiento.

Los updates de alta frecuencia (`timeupdate` en web, `addPeriodicTimeObserver` en Swift)
**no** pasan por el hook — la posición se interpola en el receptor (ver §4).

**No hacer: partir la interfaz `storer`** (`router.go:23`, ~70 métodos). Connect le suma
2-3. Romperla mueve mucha superficie sin pagar nada; el hub entra como parámetro propio de
`NewRouter`, igual que `catalogSyncer`.

Orden: R1 → R3 → R2.

### Fase 1 — Backend hub (sin clientes)
- [ ] `backend/internal/connect/` : `hub.go`, `types.go`, `hub_test.go`
- [ ] `backend/internal/api/connect.go` : los 7 handlers
- [ ] Registrar rutas en `router.go`, inyectar hub en `main.go`
- [ ] **Arreglar `WriteTimeout`** en `main.go` (bloqueante para todo lo demás)
- [ ] Tabla `playback_state` + persistencia debounced en `store/`
- [ ] Verificación: `curl -N --cookie "sid=..." localhost:8080/connect/events` recibe `hello`,
      sigue vivo >2 min, y un `POST /connect/state` desde otra terminal aparece en el stream.

### Fase 2 — Web
- [ ] `lib/connect.ts` + `lib/stores/connect.ts`
- [ ] Guards de modo remoto en `stores/player.ts`
- [ ] Device picker en `PlayerBar` + banner "Sonando en X"
- [ ] Nombre de device editable en `/settings`
- [ ] Verificación: dos pestañas, una controla a la otra; cerrar la activa libera el rol en <45s.

### Fase 3 — macOS
- [ ] `ConnectService.swift` (SSE por `URLSession.bytes`)
- [ ] Guards remotos + apagado de Now Playing en `PlayerService.swift`
- [ ] `DevicePickerView` en `PlayerBarView`
- [ ] Verificación: web controla la app nativa y viceversa; media keys del Mac controlan
      la web cuando el Mac es espectador.

### Fase 4 — Pulido
- [ ] `transfer` con handoff de posición (arranca donde iba, ±1s)
- [ ] Reconexión con backoff + `Last-Event-ID`
- [ ] Restaurar estado persistido al primer device que se conecta tras reinicio del backend
- [ ] Iconos por tipo de device, "este dispositivo" marcado
- [ ] Actualizar `docs/API.md` con la sección `/connect` y `CURRENT.md`

---

## 7. Riesgos conocidos

| Riesgo | Mitigación |
|---|---|
| `WriteTimeout: 60s` corta el SSE | Fase 1, primer ítem. Sin esto todo lo demás parece roto. |
| Traefik / cross-origin: cookie `sid` en el SSE | Ya existe `SameSite=None; Secure` para el homelab; `EventSource` necesita `{withCredentials: true}`. |
| Tormenta de updates de posición | Publicar cada 5s + interpolar en el cliente. Rate limit en el backend como red. |
| Dos pestañas con el mismo device id | `sessionStorage`, no `localStorage`. |
| Modo remoto rompe la reproducción local si el backend cae | Modo Desconectado = comportamiento actual intacto. Nunca bloquear play por falta de SSE. |
| macOS pelea el Now Playing en modo espectador | Desactivar `MPRemoteCommandCenter` al pasar a remoto. |
| Tracks locales (`OfflineStore`) no existen en el otro device | Cada device resuelve su propia fuente (local si la tiene, si no `/stream`). La cola sólo lleva ids. |
