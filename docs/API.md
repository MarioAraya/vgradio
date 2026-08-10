# API — Contrato HTTP (cliente ↔ backend)

> Contrato compartido. Cambiarlo rompe el cliente → **ask first** (ver boundaries).
> Base URL por defecto: `http://localhost:8080`. JSON salvo streams de audio.
> v1.

---

## Convenciones
- Content-Type `application/json` salvo audio.
- IDs de álbum = string estable (hash de la `sourceURL`).
- Errores: `{ "error": "mensaje legible" }` + status code apropiado.

---

## Endpoints

### POST /albums
Encola scrape de un álbum. **No bloquea** (asíncrono).

Request:
```json
{ "url": "https://origen.example/album/metroid-prime" }
```
Response `202 Accepted`:
```json
{ "jobId": "job_abc123", "albumId": "alb_7f3a", "status": "pending" }
```
Si el álbum ya está cacheado (`done`): `200 OK` con `{ "albumId": "...", "status": "done" }`.
Forzar re-scrape: `POST /albums?refresh=true`.

Errores: `400` URL inválida; `422` URL no permitida (anti-SSRF, IP privada).

---

### GET /jobs/{jobId}
Estado del scrape (polling desde el cliente).

Response `200`:
```json
{
  "jobId": "job_abc123",
  "albumId": "alb_7f3a",
  "status": "running",
  "error": null,
  "startedAt": "2026-06-06T12:00:00Z",
  "finishedAt": null
}
```
`status` ∈ `pending | running | done | failed`.

---

### GET /albums
Lista de álbumes cacheados (resumen).

Response `200`:
```json
[
  {
    "id": "alb_7f3a",
    "title": "Metroid Prime",
    "platform": "GC",
    "year": 2002,
    "coverUrl": "/albums/alb_7f3a/covers/0",
    "trackCount": 72
  }
]
```

---

### GET /albums/{albumId}
Detalle completo.

Response `200`:
```json
{
  "id": "alb_7f3a",
  "sourceUrl": "https://origen.example/album/metroid-prime",
  "title": "Metroid Prime",
  "altTitle": "メトロイドプライム",
  "platform": "GC",
  "year": 2002,
  "developer": "Retro Studios",
  "publisher": "Nintendo",
  "albumType": "Gamerip",
  "description": "…",
  "covers": [
    { "url": "/albums/alb_7f3a/covers/0", "width": 300, "height": 300 }
  ],
  "tracks": [
    {
      "id": "trk_001",
      "index": 1,
      "name": "Title",
      "durationSec": 128,
      "sizeBytes": 4214783,
      "streamUrl": "/tracks/trk_001/stream",
      "downloadUrl": "/tracks/trk_001/download"
    }
  ],
  "comments": [
    { "author": "user1", "body": "great rip", "postedAt": "2020-10-26T00:00:00Z" }
  ],
  "scrapedAt": "2026-06-06T12:00:30Z"
}
```
`404` si no existe.

---

### GET /tracks/{trackId}/stream
Stream del MP3. **Soporta `Range`** (seek/streaming).
- Sin Range: `200 OK`, `Content-Type: audio/mpeg`, body completo.
- Con `Range: bytes=N-`: `206 Partial Content` + `Content-Range`.

### GET /tracks/{trackId}/download
MP3 completo con `Content-Disposition: attachment` (offline).

### GET /albums/{albumId}/covers/{idx}
Imagen de carátula (`image/jpeg` | `image/png`).

---

## Catálogo (fase 1.5)

Índice ligero pre-scrapeado, navegable y buscable sin disparar scrape completo.

### POST /catalog/sync
Scrapea las páginas índice del origen (Browse All / por letra / por plataforma) y
puebla las `CatalogEntry`. Async (devuelve `jobId` como `/albums`). Idempotente (upsert).

### GET /catalog
Busca/lista entradas. Búsqueda general estilo Spotlight + filtros.

Query params:
- `q` — texto libre (matchea título; futuro: fuzzy).
- `platform` — ej. `SNES` (filtro).
- `letter` — inicial del título (`A`..`Z`, `#`).
- `type` — `Arrangement | Gamerip | Soundtrack | ...`.
- `limit`, `offset` — paginación (default 50 / 0).

Response `200`:
```json
{
  "total": 1234,
  "items": [
    {
      "id": "alb_7f3a",
      "title": "Super Mario World",
      "platforms": ["SNES"],
      "albumType": "Gamerip",
      "year": 1991,
      "thumbUrl": "/catalog/alb_7f3a/thumb",
      "sourceUrl": "https://origen.example/album/super-mario-world",
      "scraped": false
    }
  ]
}
```

Elegir una entrada con `scraped:false` → cliente hace `POST /albums { url: sourceUrl }`
para el scrape completo, luego `GET /albums/{id}`.

### GET /catalog/platforms
Lista de consolas/plataformas distintas (para filtros del cliente).
```json
["3DS","Arcade","GBA","NES","PS1","SNES","Switch","Windows"]
```

---

## Connect — control remoto entre instancias

Todas requieren sesión (`sid`). El backend es un **relay con estado**: no reproduce ni
interpreta la cola. Un usuario tiene N *devices* vivos y como mucho **uno activo**, que es
el único que puede publicar estado. Ver `PLAN.md` para el diseño completo.

Límites: 8 devices por usuario, TTL de 45s (heartbeat por `POST /connect/devices`, por el
ping del SSE o por cualquier `state`/`command`).

### GET /connect/events
SSE. Query: `deviceId` (obligatorio), `name`, `type`. Registra el device si no existe, así
una reconexión tras expirar el TTL no necesita un request extra.

Eventos: `hello` (snapshot inicial), `state`, `devices`, `command` (sólo al destinatario),
`transfer`. Keepalive `: ping` cada 15s.

```
event: hello
data: {"deviceId":"mac1","activeDeviceId":"","state":{…},"devices":[…]}
```

### POST /connect/devices
Registro y heartbeat (idempotente). Body: `{ "id", "name", "type", "capabilities": [] }`.
`type` ∈ `macos | web | tv`. → `200` con el device. `429` si se llegó al límite.

### GET /connect/devices → `200` lista de devices vivos
### DELETE /connect/devices/{id} → `204` (baja limpia)

### POST /connect/state?deviceId=…
Publica estado. **Sólo el device activo**; otro da `409`. El `rev` lo asigna el backend.

```json
{ "isPlaying": true, "positionSec": 42, "volume": 0.8, "isMuted": false,
  "isShuffle": false, "repeatMode": "off", "queueIndex": 0, "coverIndex": 0,
  "queue": [ { "trackId": "trk_1", "albumId": "alb_1" } ] }
```

La cola lleva **sólo IDs**: el cliente hidrata con `GET /albums/{id}`, que ya cachea.

La posición se publica en cambios discretos y cada ~5s; los espectadores la **interpolan**
desde `positionSec` + `updatedAt` en vez de pedir un update por segundo.

### POST /connect/command?deviceId=…
Body: `{ "targetDeviceId"?, "type", "payload"? }`. Sin `targetDeviceId` va al activo.
→ `202`. `400` si el `type` no está en la allowlist; `404` si el device no es del usuario.

`type` ∈ `play | pause | toggle | next | prev | seek | volume | mute | shuffle | repeat |
playContext | queueAdd | queueRemove | queueMove`.

`playContext` (`{albumId|playlistId, startTrackId, shuffle}`) deja que el device activo
arme la cola desde su propia fuente en vez de mandar 72 ítems.

### POST /connect/transfer
Body: `{ "deviceId", "play" }`. Reclama el rol activo → `200` con el estado. El device
anterior se entera por el evento `transfer`; no se le pregunta.

---

## Notas de versionado
- v1 sin auth (self-host, red local).
- Cambios incompatibles → prefijo `/v2` o header de versión (decidir en su momento, ask first).
