# Spec: VGRadio Web Frontend (SvelteKit)

## Objetivo

Frontend web que replica la app macOS en el browser. Usuario único (tú), corre localmente contra el mismo backend Go en `localhost:8080`. Sin autenticación, sin SSR. Permite usar VGRadio en cualquier OS con un browser.

**Éxito:** paridad funcional con el cliente SwiftUI — reproducir, explorar catálogo, manejar favoritos/wishlist, cola de reproducción.

---

## Tech Stack

| Capa | Elección | Razón |
|---|---|---|
| Framework | SvelteKit (SPA mode) | Stores reactivos nativos, bundle pequeño, sin virtual DOM |
| Estilos | CSS variables + scoped styles | Sin dependencia extra, design system mapeado directo |
| Audio | HTML5 `<audio>` | Nativo del browser, soporta streaming por redirect 302 |
| Estado persistente | `localStorage` | Equivalente a `UserDefaults` del cliente macOS |
| Fetching | `fetch` nativo | Sin libs extra |
| Build | Vite (incluido en SvelteKit) | |
| Lenguaje | TypeScript | |

---

## Comandos

```bash
# Instalar
npm install

# Dev
npm run dev           # http://localhost:5173

# Build
npm run build         # output en build/

# Preview build
npm run preview

# Type check
npm run check

# Lint
npm run lint
```

---

## Estructura del Proyecto

```
web/                          ← raíz del frontend (nuevo directorio en el repo)
├── src/
│   ├── app.html              ← shell HTML
│   ├── app.css               ← variables CSS del design system + reset
│   ├── lib/
│   │   ├── api.ts            ← cliente HTTP (todos los endpoints del backend)
│   │   ├── types.ts          ← tipos TypeScript (mirror de Models.swift)
│   │   ├── stores/
│   │   │   ├── player.ts     ← estado del reproductor (svelte store)
│   │   │   ├── favorites.ts  ← favoritos (persistido en localStorage)
│   │   │   ├── wishlist.ts   ← wishlist (persistido en localStorage)
│   │   │   ├── hidden.ts     ← tracks ocultos (persistido en localStorage)
│   │   │   └── coverPrefs.ts ← cover index preferido por álbum (localStorage)
│   │   └── components/
│   │       ├── PlayerBar.svelte
│   │       ├── QueuePanel.svelte
│   │       ├── Sidebar.svelte
│   │       ├── AlbumGrid.svelte
│   │       ├── AlbumCard.svelte
│   │       ├── AlbumDetail.svelte
│   │       ├── TrackRow.svelte
│   │       ├── FavoritesView.svelte
│   │       ├── BrowseView.svelte
│   │       ├── WishlistView.svelte
│   │       ├── AddURLModal.svelte
│   │       ├── SearchOverlay.svelte
│   │       └── LetterStrip.svelte
│   └── routes/
│       └── +page.svelte      ← SPA shell (toda la navegación es client-side)
├── static/
├── svelte.config.js          ← adapter-static, SPA mode
├── vite.config.ts
├── tsconfig.json
└── package.json
```

---

## Design System (CSS variables)

```css
/* app.css */
:root {
  --bg:          #131320;
  --sidebar:     #0F0F1A;
  --surface:     #17172A;
  --surface-hi:  #1C1C30;
  --muted:       #1B1B2C;
  --accent:      #CBA827;
  --accent-soft: rgba(203, 168, 39, 0.10);
  --accent-bg:   rgba(203, 168, 39, 0.08);
  --text:        #F0F0F5;
  --text-sec:    #8A8AA0;
  --text-muted:  rgba(138, 138, 160, 0.60);
  --separator:   rgba(255, 255, 255, 0.08);
  --border60:    rgba(255, 255, 255, 0.048);

  --player-bar-h: 72px;
  --sidebar-w:    220px;
  --radius-sm:    5px;
  --radius-md:    8px;
  --radius-lg:    12px;

  --sp-xs: 4px;
  --sp-sm: 8px;
  --sp-md: 16px;
  --sp-lg: 24px;
  --sp-xl: 32px;
}
```

---

## Tipos TypeScript (lib/types.ts)

```ts
export interface AlbumSummary {
  id: string
  title: string
  platform: string
  year: number
  albumType: string
  trackCount: number
  coverUrls: string[]
}

export interface Album extends AlbumSummary {
  altTitle: string
  developer: string
  publisher: string
  catalogNumber: string
  description: string
  sourceUrl: string
  covers: Cover[]
  tracks: Track[]
  comments: Comment[]
}

export interface Track {
  id: string
  index: number
  name: string
  durationSec: number
  sizeBytes: number
  streamUrl: string
  downloadUrl: string
  downloaded: boolean
}

export interface Cover { url: string; width: number; height: number }
export interface Comment { author: string; body: string; postedAt: string }

export interface ScrapeJob {
  jobId: string
  albumId: string
  status: 'pending' | 'running' | 'done' | 'failed'
  error?: string
}

export interface CatalogEntry {
  title: string
  sourceUrl: string
  platform: string
  year: number
}

export interface CatalogPage {
  total: number
  offset: number
  limit: number
  items: CatalogEntry[]
}

export interface CatalogConsole {
  id: string
  name: string
  url: string
  albumCount: number
}

export interface CatalogSyncProgress {
  running: boolean
  total: number
  done: number
  errors: number
  entries: number
  consoles: number
}

export interface FavoriteTrack {
  id: string
  name: string
  albumId: string
  albumTitle: string
  platform: string
  year: number
  durationSec: number
}

export interface WishlistItem { url: string }
```

---

## API Client (lib/api.ts)

Wrapper delgado sobre `fetch`. URL base configurable vía `localStorage` (default `http://localhost:8080`).

```ts
const BASE = () => localStorage.getItem('vgradio.backendURL') ?? 'http://localhost:8080'

// Todos los endpoints:
albums()                                    // GET /albums → AlbumSummary[]
album(id)                                   // GET /albums/:id → Album
addAlbum(url)                               // POST /albums → ScrapeJob
job(id)                                     // GET /jobs/:id → ScrapeJob
streamURL(track)                            // string: BASE + track.streamUrl
downloadURL(track)                          // string: BASE + track.downloadUrl
fetchTrack(trackId)                         // POST /tracks/:id/fetch
catalog(params)                             // GET /catalog?q&platform&letter&offset&limit
catalogConsoles()                           // GET /catalog/consoles
startCatalogSync()                          // POST /catalog/sync
catalogSyncProgress()                       // GET /catalog/sync
setCFClearance(value)                       // PUT /config/cf-clearance
coverURL(url)                               // prefija BASE si es path relativo /covers/...
recordPlay(trackId, albumId)                // POST /history
history(limit?)                             // GET /history?limit=N → HistoryEntry[]
```

---

## Stores

### player.ts

Estado reactivo del reproductor. `writable` store con este shape:

```ts
interface PlayerState {
  queue: Track[]
  queueIndex: number
  currentAlbum: AlbumSummary | null
  currentCovers: Cover[]
  currentCoverIndex: number
  isPlaying: boolean
  currentTime: number
  duration: number
  volume: number          // 0-1, persiste en localStorage
  isMuted: boolean
  isShuffle: boolean
  repeatMode: 'off' | 'all' | 'one'
  showQueue: boolean
}
```

Funciones exportadas:
- `play(track, album, queue, covers)` — carga y reproduce
- `togglePlay()`
- `next()` — respeta shuffle, repeat, hidden tracks
- `previous()` — si currentTime > 3s → seek(0), sino track anterior
- `seek(seconds)`
- `playNext(track)` — inserta en queueIndex+1
- `removeFromQueue(index)`
- `moveInQueue(from, to)`
- `setVolume(v)` / `toggleMute()`
- `setRepeat(mode)` / `toggleShuffle()`

Audio: un singleton `<audio>` element creado en `player.ts`. Eventos `timeupdate`, `ended`, `loadedmetadata` actualizan el store.

### favorites.ts

Persistido en `localStorage` como `vgradio.favorites` (array JSON de `FavoriteTrack`).

- `isFavorite(trackId)` → bool
- `toggle(track, album)` — add/remove
- `addAll(tracks, album)`
- `removeAll(albumId)`
- `isAlbumFavorited(albumId)` → bool
- `grouped` → derived: `[(albumTitle, platform, year, tracks[])]`

### wishlist.ts

Persistido en `localStorage` como `vgradio.wishlist`. Incluye las mismas URLs default del cliente macOS.

- `add(url)`
- `remove(url)`

### hidden.ts

Persistido en `localStorage` como `vgradio.hiddenTracks` (Set serializado como array).

- `isHidden(trackId)` → bool
- `toggle(trackId)`

### coverPrefs.ts

Persistido en `localStorage` como `vgradio.coverPrefs` (`{[albumId]: number}`).

- `get(albumId)` → number (default 0)
- `set(albumId, index)`

---

## Vistas / Componentes

### Layout general

```
┌─────────────────────────────────────────────────────────┐
│  Sidebar (220px)  │  Content area (flex: 1)             │
│                   │                                      │
│  • Library        │  <LibraryView | BrowseView |         │
│  • Browse         │   FavoritesView | WishlistView |     │
│  • Favorites      │   RecentlyPlayedView>                │
│  • Wishlist       │                                      │
│  • Recent         │                                      │
│  • [+ Add URL]    │                                      │
├───────────────────┴──────────────────────────────────────┤
│  PlayerBar (72px fijo al fondo)                          │
└─────────────────────────────────────────────────────────┘
```

### Sidebar

- Íconos + label para cada sección
- Botón "+ Add URL" abre `AddURLModal`
- Item activo resaltado con `var(--accent)`

### LibraryView

- Grid de `AlbumCard` (120×120px cover art + título + plataforma/año)
- Click en card → `AlbumDetail` (inline, reemplaza grid)
- Loading skeleton mientras carga
- Estado vacío con instrucción "Add albums with + Add URL"

### AlbumDetail

- Cover art grande (220px) — múltiples covers navegables (← →)
  - Cover index sincronizado con `coverPrefs` store
- Metadata: título, alt-title, platform, year, developer, publisher, catalog number, album type
- Botones: "Play All", "Shuffle All"
- Tracklist: tabla con columnas `#`, nombre, duración, `▶+` (play next), ★ (favorito), 👎 (ocultar)
  - Row activo resaltado con `var(--accent-bg)`
  - Doble-click o click en nombre → play track
  - Hover revela botones de acción
- Botón "← Back" vuelve a la library grid
- Botón "Favorite Album" / "Unfavorite Album" (favorita todos los tracks)
- Indicador de descarga por track (punto verde si `downloaded`)

### BrowseView

- Search input (debounce 300ms)
- Sync status + botón "Sync Catalog" (polling cada 1.5s mientras `running`)
- `LetterStrip`: botones "All", "0-9", A-Z
- Console picker: chips horizontales scrollables ("All", + una por consola)
- Lista paginada de `CatalogEntry` — scroll infinito (loadMore al llegar al último item)
  - Cada fila: título, platform, year, botón `+` al hover → importa album
  - Estado post-import: checkmark verde

### FavoritesView

- Header con "Play All" button
- Agrupado por álbum: header de grupo (albumTitle, platform, year) + lista de tracks
- Cada track: nombre, duración, ★ para quitar de favoritos
- Click en track → play (con la lista de ese grupo como queue)

### RecentlyPlayedView

- Lista cronológica inversa de reproducciones (últimas 100)
- Cada fila: cover miniatura (44px), track name, album name, platform, tiempo relativo ("hace 5 min")
- Click en fila → play track (carga queue del álbum entero)
- Click en album name → navega a AlbumDetail

### WishlistView

- Lista de URLs con display title (slug formateado)
- Botón "Import" por item → llama `addAlbum` y espera job, muestra progreso
- Botón "Remove" para cada item
- Input + "Add URL" para agregar nueva URL

### AddURLModal

- Modal overlay, fondo dimmed
- Input de URL con label "Paste khinsider album URL"
- Botón "Add" → `addAlbum()` → polling del job → cierra al completar / muestra error
- Progress states: idle → loading → "Scraping…" → done / error
- Cerrar: botón X, click fuera, Escape

### PlayerBar (72px, fijo en fondo)

```
[← ▶ →] [0:00/3:45]  [cover 44px] [track name / album]  [🔊 vol] [★] [⟳] [⇀] [≡]
                       ────────── progress scrubber (barra completa arriba) ──────────
```

Secciones:
1. **Transport**: prev, play/pause (círculo blanco), next + tiempo actual/total
2. **Cover + info**: cover clickable (→ navega al álbum), track name, album name
3. **Volume**: icono mute toggle, slider aparece en hover
4. **Star**: favoritar track actual
5. **Secondary**: repeat (off/all/one), shuffle (toggle), queue button
6. **Scrubber**: barra fina encima de toda la barra, draggable/clickable

### QueuePanel

- Overlay 320×420px sobre el player bar (bottom-right)
- Lista scrollable de tracks en queue
- Track actual destacado + indicador de onda animada
- Drag & drop para reordenar (HTML5 drag o pointer events)
- Botón × por fila para quitar de queue
- Botón × para cerrar panel

### SearchOverlay

- Overlay full-screen con input enfocado
- Busca en `albums` locales (título, plataforma) en tiempo real
- Click en resultado → navega a AlbumDetail
- Cerrar: Escape, click fuera

---

## Atajos de Teclado

| Tecla | Acción |
|---|---|
| `Space` | Play/Pause |
| `Cmd/Ctrl + K` | Abrir búsqueda |
| `Cmd/Ctrl + 1` | Library |
| `Cmd/Ctrl + 2` | Browse |
| `Cmd/Ctrl + 3` | Favorites |
| `Cmd/Ctrl + 4` | Add URL modal |
| `Escape` | Cerrar modal/overlay activo |

---

## Routing (SPA)

SvelteKit en modo SPA (`adapter-static` + fallback). Un solo `+page.svelte` maneja todo. Navegación interna via store (`activeView: 'library' | 'browse' | 'favorites' | 'wishlist'`). Sin URL routing complejo — es app local.

---

## Testing

- Vitest para unit tests de stores y api client
- Tests de stores: favorites, wishlist, hidden, coverPrefs
- Tests de api client: mock fetch, verificar paths y métodos HTTP correctos
- Sin tests de UI (Playwright sería overkill para app personal local)

```bash
npm run test        # vitest
npm run test:watch  # watch mode
```

---

## Boundaries

**Siempre:**
- TypeScript estricto (`strict: true` en tsconfig)
- CSS variables del design system, nunca valores hardcodeados
- Svelte stores para estado compartido, no prop drilling
- Persisetir en localStorage lo mismo que el cliente macOS persiste en UserDefaults

**Pedir primero:**
- Agregar dependencias npm (actualmente: ninguna excepto SvelteKit + Vite)
- Cambiar estructura de rutas
- Modificar el backend Go

**Nunca:**
- Agregar autenticación (app local, no necesaria)
- SSR (adapter-static solamente)
- Duplicar lógica de scraping (eso es trabajo del backend)
- Guardar datos en el server-side desde el frontend

---

## Criterios de Éxito

- [ ] Player reproduce audio vía `GET /tracks/:id/stream` sin pre-descarga
- [ ] Library muestra grid de álbumes descargados, navega a detail
- [ ] AlbumDetail muestra covers navegables, tracklist completa, play/pause por track
- [ ] PlayerBar visible en todas las vistas con progreso en tiempo real y scrubber funcional
- [ ] Favoritos persisten entre recargas (localStorage)
- [ ] Browse muestra catálogo con búsqueda, filtro por letra y por consola
- [ ] Browse permite importar album desde el catálogo
- [ ] Queue panel muestra cola, permite reordenar y quitar tracks
- [ ] Shuffle, repeat (off/all/one) funcionan igual que en el cliente macOS
- [ ] Hidden tracks son saltados por next/shuffle
- [ ] Wishlist persiste y permite importar URLs
- [ ] `npm run build` produce un bundle sin errores

---

## Decisiones

1. **Recently Played** — implementar con persistencia en el backend (SQLite). Requiere endpoint nuevo en Go: `POST /history` (registrar reproducción) y `GET /history` (últimos N). El store web llama `POST /history` cada vez que cambia el track.
2. **Backend URL** — hardcodeado `http://localhost:8080`, guardado en `localStorage` sin UI de configuración.
3. **CF-Clearance** — no exponer en UI; se setea vía variable de entorno en el backend.
4. **Branch** — `web`.
