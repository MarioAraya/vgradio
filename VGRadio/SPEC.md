# SPEC — Cliente macOS (VGRadio, SwiftUI)

> Reproductor nativo macOS, ligero y bonito (ref: *Tiny Player*). Pega URL de álbum,
> el backend la scrapea, y aquí se navega la biblioteca y se reproduce.
> Padre: [`../SPEC.md`](../SPEC.md). Contrato: [`../docs/API.md`](../docs/API.md).

---

## 1. Objetivo

App SwiftUI (macOS 14+) que:
1. Deja **agregar álbumes pegando una URL** (envía al backend, hace polling del job).
2. Muestra **biblioteca** de álbumes cacheados (carátula, título, metadata).
3. **Reproduce** tracks vía AVFoundation (stream o local), con cola play/pause/seek/next/prev.
4. Permite **descargar** un álbum para escucha offline.

---

## 2. Pantallas (v1)

```
┌──────────────┬───────────────────────────────────────┐
│  Sidebar     │  Detalle de álbum                      │
│              │  ┌────────┐  Metroid Prime             │
│  Biblioteca  │  │ cover  │  GC · 2002 · Retro Studios │
│  + Add URL   │  └────────┘  Gamerip                   │
│              │  ───────────────────────────────────── │
│  [álbum 1]   │  1. Title              2:08   ▸  ⤓     │
│  [álbum 2]   │  2. Menu Select        1:52   ▸  ⤓     │
│  ...         │  ...                                   │
├──────────────┴───────────────────────────────────────┤
│  ◀  ▮▮  ▶   Title — Metroid Prime    ──●───── 00:00   │  ← mini-player (siempre visible)
└───────────────────────────────────────────────────────┘
```

1. **Library** — grid/lista de álbumes (ya scrapeados) + botón "Add URL".
2. **Add URL sheet** — input URL → POST al backend → polling de estado (pending/running/done).
3. **Album detail** — metadata, carátula, tracklist, descripción, comentarios.
4. **Player bar** — persistente abajo: transport + scrubber + track actual.

### Fase 1.5 — Catálogo navegable
5. **Catalog / Browse** — lista del catálogo pre-scrapeado (`GET /catalog`) con:
   - Buscador general estilo **Spotlight** (`q`, debounce) — atajo `⌘F` / `⌘K`.
   - Filtros por **consola** (`platform`) y por **letra inicial** (`letter`).
   - Tabla: thumb · título · plataformas · tipo · año (ref. imágenes de diseño).
   - Tap en entrada `scraped:false` → `POST /albums` + polling → añade a biblioteca.

---

## 3. Estructura

```
VGRadio/
├── SPEC.md
├── Package.swift               # o VGRadio.xcodeproj
└── Sources/VGRadio/
    ├── App/                    # VGRadioApp, WindowGroup
    ├── Models/                 # Album, Track, Cover, Comment, ScrapeJob (Codable)
    ├── Services/
    │   ├── APIClient.swift     # async/await, mapea docs/API.md
    │   └── PlayerService.swift # AVQueuePlayer wrapper
    ├── Stores/
    │   └── LibraryStore.swift  # @Observable, estado biblioteca
    └── Views/
        ├── LibraryView.swift
        ├── AddURLView.swift
        ├── AlbumDetailView.swift
        └── PlayerBarView.swift
```

---

## 4. Servicios

- **APIClient**: `addAlbum(url)`, `jobStatus(id)`, `albums()`, `album(id)`,
  `streamURL(trackID)`, `download(trackID)`. `async/await` + `URLSession`.
- **PlayerService**: envuelve `AVQueuePlayer`. API: `play(track, in: album)`, `pause()`,
  `next()`, `previous()`, `seek(to:)`, publica `currentTime`, `isPlaying`, `currentTrack`.
- **LibraryStore** `@Observable`: lista de álbumes, álbum seleccionado, refresco tras add.

---

## 5. Comandos

```bash
cd VGRadio
swift build                     # si Package.swift
swift test                      # XCTest
# o Xcode: ⌘B build, ⌘U test
```

Config backend base URL por `UserDefaults` / settings (default `http://localhost:8080`).

---

## 6. Estilo / UX

- SwiftUI declarativo, `@Observable`, `async/await`. Sin fuerza-unwrap salvo invariante.
- Diseño limpio: tipografía clara, carátula protagonista, transporte minimalista.
- Estados explícitos: loading / empty / error en cada vista async.

---

## 7. Testing (TDD básico v1)

| Test | Cubre |
|------|-------|
| Models decode | JSON de ejemplo (de `docs/API.md`) → structs sin error |
| APIClient | con `URLProtocol` mock: parsea respuestas, maneja error/timeout |
| PlayerService | lógica de cola: next/prev avanza índice, wrap, estado |

UI/snapshot tests aplazados post-v1.

---

## 8. Boundaries

- **Always:** estados loading/error visibles; base URL configurable (no hardcode).
- **Ask first:** dependencias externas (preferir frameworks Apple); cambiar UX núcleo.
- **Never:** bloquear el main thread en red/IO; asumir que el job termina (siempre polling con timeout).
