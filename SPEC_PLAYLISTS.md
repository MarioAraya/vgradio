# SPEC — Feature: Playlists de Usuario

> Fase 2 del roadmap. Define qué se construye antes del cómo.
> Última revisión: 2026-06-22.

---

## 1. Objetivo

Permitir que usuarios autenticados creen y gestionen **playlists personales** de tracks.
Los "Favoritos" (⭐) se tratan como una playlist automática especial ("Liked Music"),
no editable ni eliminable. Estilo de referencia: YouTube Music.

### Usuarios objetivo
Mismos que el resto de VGRadio: uso personal/archival, self-host.

---

## 2. Reglas de negocio

| Regla | Detalle |
|-------|---------|
| "Liked Music" | Auto-playlist virtual. Lee `track_favorites`. No se puede renombrar/eliminar. |
| Playlists de usuario | CRUD completo. El dueño puede editar nombre, descripción, privacidad. |
| Privacidad | `private` (solo el dueño la ve) o `public` (cualquiera puede leerla, sin auth). |
| Posición de tracks | Cada track tiene `position` (entero). Se puede reordenar. |
| Tracks duplicados | Un mismo track puede estar en la misma playlist solo una vez. |
| Reproducción | Play desde la playlist carga todos sus tracks en el queue del player. |
| Sin auth | Solo playlists públicas accesibles. Mutations siempre requieren auth. |

---

## 3. Backend — Go / SQLite

### 3.1 Schema (migraciones idempotentes)

```sql
CREATE TABLE IF NOT EXISTS playlists (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    is_public   INTEGER NOT NULL DEFAULT 0,   -- 0=private, 1=public
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
CREATE INDEX IF NOT EXISTS idx_playlists_user ON playlists(user_id);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL DEFAULT 0,
    added_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    PRIMARY KEY (playlist_id, track_id)
);
CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id, position);
```

### 3.2 API Endpoints

Todos bajo `/playlists`. Requieren `requireAuth` salvo donde se indica.

```
GET    /playlists                   # lista playlists propias (auth) + públicas de otros
POST   /playlists                   # crear playlist (auth)
GET    /playlists/{id}              # leer playlist + tracks (auth si privada, public si pública)
PATCH  /playlists/{id}             # editar name/description/is_public (dueño)
DELETE /playlists/{id}             # eliminar playlist (dueño)
POST   /playlists/{id}/tracks      # body: {trackId, position?} — añadir track (dueño)
DELETE /playlists/{id}/tracks/{trackId}  # quitar track (dueño)
PUT    /playlists/{id}/tracks/reorder    # body: [{trackId, position}] — reordenar (dueño)
```

### 3.3 JSON shapes

**PlaylistSummary** (en listados):
```json
{
  "id": "abc123",
  "name": "VGM favorites",
  "description": "",
  "isPublic": false,
  "trackCount": 12,
  "totalDurationSec": 3600,
  "coverUrls": ["..."],
  "ownerId": "uid",
  "ownerName": "Mario",
  "createdAt": "2026-06-22T..."
}
```

**PlaylistDetail** (en `GET /playlists/{id}`):
```json
{
  "id": "...",
  "name": "...",
  "description": "...",
  "isPublic": false,
  "ownerId": "...",
  "ownerName": "...",
  "createdAt": "...",
  "updatedAt": "...",
  "tracks": [
    {
      "position": 0,
      "id": "123",
      "name": "Boss Battle",
      "albumId": "...",
      "albumTitle": "Mega Man 2",
      "platform": "NES",
      "year": 1988,
      "durationSec": 120,
      "streamUrl": "/tracks/123/stream",
      "coverUrl": "..."
    }
  ]
}
```

### 3.4 Lógica de acceso

```
GET /playlists/{id}:
  - si is_public=1 → acceso libre
  - si is_public=0 → requiere auth + user_id == playlist.user_id
  - si no existe → 404

PATCH / DELETE / POST tracks:
  - requiere auth
  - 403 si user_id != playlist.user_id
```

### 3.5 Archivos a modificar / crear

- `backend/internal/store/store.go` — `migrate()` agrega tablas `playlists` + `playlist_tracks`
- `backend/internal/store/playlists.go` — CRUD de playlists (nuevo archivo)
- `backend/internal/api/handlers.go` — nuevos handlers, registro en `NewMux`
- `backend/internal/api/handlers.go` `storer` interface — añadir métodos de playlists

---

## 4. Web — SvelteKit

### 4.1 Nuevas rutas

```
/playlists          →  lista todas (redirect a /playlists/liked si solo hay una?)
/playlists/liked    →  auto-playlist "Liked Music" (lee track_favorites existente)
/playlists/[id]     →  playlist de usuario
```

### 4.2 Componentes nuevos

| Componente | Descripción |
|-----------|-------------|
| `PlaylistEditModal.svelte` | Modal para crear/editar: campos name, description, privacy select |
| `AddToPlaylistModal.svelte` | Modal para elegir playlist al añadir un track |
| `PlaylistDetail.svelte` o ruta | Vista detalle: cover mosaico, metadata, botones (play, lápiz, más), track list |

### 4.3 Sidebar

```
─────────────────
  ★ Liked Music       ← auto-playlist (siempre visible si hay sesión)
─────────────────
  + New playlist
  My playlist 1
  My playlist 2
─────────────────
```

- "Liked Music" siempre primero, con ícono ★ y badge "Auto playlist".
- "+ New playlist" abre `PlaylistEditModal` para crear.
- Cada playlist muestra nombre + dueño (o "Auto playlist").
- Al hacer click → navega a `/playlists/[id]` (o `/playlists/liked`).

### 4.4 Vista Detalle de Playlist

Inspirada en la imagen 2 (YouTube Music):

```
[Cover mosaico 4 tracks]   Tracks list:
 Playlist Name             ─────────────────────────
 @ownerName                [thumb] Track name - Album    ♥  4:44
 Private • 2026            [thumb] Track name - Album    ♥  6:37
 12 tracks • 2h 30m        ...
 [⬇] [✏] [▶] [↗] [•••]
```

- **▶ Play** carga todos los tracks de la playlist en el player queue.
- **✏ Lápiz** abre `PlaylistEditModal` en modo edición.
- Tracks mostrán thumb del álbum + nombre + álbum + duración.
- Click en track → empieza reproducción desde esa posición.

### 4.5 Menú contextual de tracks

En la fila de un track (en AlbumDetail y FavoritesView), añadir opción:
- **"Add to playlist…"** → abre `AddToPlaylistModal` con lista de playlists del usuario.

### 4.6 Stores

```
web/src/lib/stores/playlists.ts
```

- `loadPlaylists()` — fetch `GET /playlists`
- `createPlaylist(name, desc, isPublic)` — POST
- `updatePlaylist(id, patch)` — PATCH
- `deletePlaylist(id)` — DELETE
- `addTrack(playlistId, trackId)` — POST tracks
- `removeTrack(playlistId, trackId)` — DELETE track

### 4.7 Tipos nuevos (`web/src/lib/types.ts`)

```typescript
export interface PlaylistSummary {
  id: string
  name: string
  description: string
  isPublic: boolean
  trackCount: number
  totalDurationSec: number
  coverUrls: string[]
  ownerId: string
  ownerName: string
  createdAt: string
}

export interface PlaylistTrack {
  position: number
  id: string
  name: string
  albumId: string
  albumTitle: string
  platform: string
  year: number
  durationSec: number
  streamUrl: string
  coverUrl?: string
}

export interface PlaylistDetail extends PlaylistSummary {
  updatedAt: string
  tracks: PlaylistTrack[]
}
```

---

## 5. macOS (Swift) — Fase posterior

**Out of scope en esta iteración.** Se implementará en fase siguiente usando los mismos
endpoints REST. Requeriría:
- `PlaylistStore.swift` (análogo a `FavoritesStore`)
- `PlaylistsView.swift` en el sidebar
- `PlaylistDetailView.swift`

---

## 6. Criterios de aceptación

### Backend
- [ ] `GET /playlists` devuelve playlists propias (auth) + públicas de otros usuarios
- [ ] `POST /playlists` crea playlist con nombre+desc+privacidad; devuelve PlaylistSummary
- [ ] `PATCH /playlists/{id}` actualiza campos; 403 si no es dueño
- [ ] `DELETE /playlists/{id}` elimina; 403 si no es dueño
- [ ] `POST /playlists/{id}/tracks` añade track con posición; 409 si ya existe
- [ ] `DELETE /playlists/{id}/tracks/{trackId}` quita track
- [ ] `PUT /playlists/{id}/tracks/reorder` reordena; valida que todos los trackIds existan en la playlist
- [ ] Playlist privada de otro usuario → 403
- [ ] Playlist pública de otro usuario → 200 sin auth

### Web
- [ ] Sidebar muestra "★ Liked Music" + lista de playlists del usuario
- [ ] "+ New playlist" abre modal y crea playlist
- [ ] Botón ✏ en detalle abre modal edición (name, description, privacy)
- [ ] ▶ Play carga todos los tracks en el queue del player
- [ ] "Add to playlist…" en menú contextual de track funciona
- [ ] Ruta `/playlists/liked` muestra track_favorites como playlist

---

## 7. Fuera de alcance en esta iteración

- Colaboración / playlists compartidas en modo edición conjunta
- Clonar playlist de otro usuario (Fase 3)
- Reorden por drag & drop (puede añadirse después; por ahora orden = posición de inserción)
- macOS app

---

## 8. Suposiciones (confirmar antes de implementar)

1. "Liked Music" usa los `track_favorites` existentes del backend (no localStorage).
2. Cover de playlist = mosaico de primeras 4 carátulas de álbumes en la playlist.
3. Al crear playlist sin tracks, el cover queda vacío/placeholder.
4. No hay votación ni colaboración (ignoro tab "COLLABORATE" de la img 3 por ahora).
5. El reorden de tracks por drag es out of scope por ahora.
