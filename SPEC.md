# SPEC — VGRadio

> Reproductor de música nativo macOS (SwiftUI) + backend scraper API (Go).
> Spec-Driven Development. Este documento define **qué** se construye antes del **cómo**.
> Estado: v1 (MVP). Última revisión: 2026-06-06.

---

## 1. Objetivo

### Problema
Sitios de música de videojuegos (estilo *khinsider*) sirven álbumes como páginas HTML
con links directos a `.mp3`. Escuchar implica navegar web fea, bajar a mano, sin
biblioteca ni reproductor decente.

### Solución
Un reproductor macOS **bonito y ligero** (referencia: *Tiny Player*, pero con mejor diseño)
donde el usuario:
1. Pega la **URL de un álbum/playlist**.
2. Un **backend Go** la scrapea de forma asíncrona, extrae metadata + carátulas +
   tracks `.mp3` + descripción + comentarios, y **cachea** el resultado (no re-scrapea).
3. El cliente **stream**ea o **descarga** los tracks y los reproduce.

### Usuarios objetivo
- Uso **personal / archival** de un único usuario (el autor) y allegados.
- Self-host en homelab (Proxmox + Gitea + Drone CI).

### Métricas de éxito (v1)
- Pegar URL de álbum → biblioteca poblada con metadata + carátula en < 30 s (primer scrape).
- Segundo acceso al mismo álbum sirve desde caché en < 1 s (sin re-scrape).
- Reproducción gapless-ish con controles play/pause/seek/next/prev funcionando.

### Roadmap
- **v1 (MVP):** agregar álbum pegando URL → scrape → reproducir.
- **Fase 1.5 — Catálogo navegable:** índice ligero pre-scrapeado de álbumes
  (título, consola/plataforma, tipo, año, thumb, sourceURL). El usuario navega/busca
  sin pegar URL y elige una entrada → dispara el scrape completo on-demand. Búsqueda
  estilo **Spotlight** (general) + filtros por consola y por letra inicial.
- **Fase 2:** P2P / seeding entre clientes (tipo torrent); pago/suscripción para
  opt-out de hosting.

### Fuera de alcance v1
- Catálogo navegable (fase 1.5).
- P2P, pago, FLAC (solo MP3 en v1), multi-usuario / auth.

---

## 2. Arquitectura

```
┌─────────────────────┐        HTTP/JSON + Range        ┌──────────────────────┐
│   Cliente macOS     │  ───────────────────────────▶  │   Backend Go (API)   │
│   VGRadio (SwiftUI) │  ◀───────────────────────────  │   scraper + cache    │
│                     │     stream / download mp3       │                      │
│  - AVFoundation     │                                 │  - goroutines scrape │
│  - biblioteca local │                                 │  - filesystem + SQLite│
└─────────────────────┘                                 └──────────┬───────────┘
                                                                    │ scrape (1x)
                                                                    ▼
                                                          ┌──────────────────┐
                                                          │  Sitio origen    │
                                                          │  (HTML + .mp3)   │
                                                          └──────────────────┘
```

### Decisiones (confirmadas)
| Tema | Decisión v1 |
|------|-------------|
| P2P | Fuera de v1. Especificado como fase 2. |
| Cache backend | Filesystem (audio) + SQLite (metadata). Cero infra externa. |
| Entrega audio | Stream (HTTP Range) **+** descarga para offline. |
| Cliente | SwiftUI puro, AVFoundation, macOS 14 Sonoma+. |
| Scrape | Asíncrono vía goroutines; job con estado (pending/running/done/failed). |

---

## 3. Componentes

Dos sub-proyectos en monorepo. Cada uno con su propio SPEC detallado:

- `backend/` → ver [`backend/SPEC.md`](backend/SPEC.md)
- `VGRadio/` (cliente) → ver [`VGRadio/SPEC.md`](VGRadio/SPEC.md)
- Contrato compartido API → ver [`docs/API.md`](docs/API.md)

---

## 4. Comandos (raíz / dev loop)

```bash
# Backend
cd backend
go run ./cmd/server          # levanta API en :8080
go test ./...                # tests unit (safety net TDD)
go build ./...               # compila

# Cliente (macOS)
cd VGRadio
xcodebuild -scheme VGRadio build
xcodebuild test -scheme VGRadio   # XCTest unit
# o abrir VGRadio.xcodeproj / Package.swift en Xcode
```

---

## 5. Estructura de proyecto (monorepo)

```
vgradio-app/
├── SPEC.md                 # este archivo (spec maestro)
├── README.md
├── docs/
│   └── API.md              # contrato HTTP cliente↔backend
├── backend/                # API scraper en Go
│   ├── SPEC.md
│   ├── go.mod
│   ├── cmd/server/
│   └── internal/
└── VGRadio/                # cliente macOS SwiftUI
    ├── SPEC.md
    └── Sources/
```

---

## 6. Estilo de código

### Go (backend)
- `gofmt` + `go vet`. Errores explícitos (`if err != nil`), nunca silenciados.
- Paquetes por dominio (`scraper`, `store`, `api`), no por capa técnica genérica.
- Interfaces pequeñas, definidas en el consumidor. Inyección de dependencias por constructor.
- Concurrencia con goroutines + channels/context; sin estado global mutable compartido.
- Código simple y legible > clever. Tests junto al código (`_test.go`).

### Swift (cliente)
- SwiftUI declarativo, `@Observable` / `@State` para estado.
- Capas: `Models`, `Services` (networking, playback), `Views`, `Stores`.
- `async/await` para red. Sin fuerza-unwrap (`!`) salvo invariantes probadas.
- Nombres descriptivos estilo Swift API Design Guidelines.

---

## 7. Estrategia de testing

> Flujo: **commit inicial de specs → TDD** con tests unit básicos como safety net
> **antes** de publicar en Gitea (Proxmox `main`) o GitHub.

| Capa | Qué se testea | Herramienta |
|------|---------------|-------------|
| Go scraper | Parseo de HTML fixture → struct álbum/tracks correcto | `go test`, fixtures HTML |
| Go store | Cache: escribir/leer álbum, idempotencia (no re-scrape) | `go test`, SQLite temp |
| Go api | Handlers: status codes, JSON shape, Range requests | `httptest` |
| Swift services | Decode de respuestas API, lógica de playback queue | XCTest |

Prioridad v1: scraper parsing + cache idempotency (núcleo del valor). UI tests aplazados.

---

## 8. Boundaries

### Always (siempre)
- Cachear resultados de scrape; **nunca** re-scrapear un álbum ya cacheado salvo refresh explícito.
- Respetar `robots.txt` y throttling (rate-limit + delay) al scrapear el sitio origen.
- Validar/sanitizar URLs de entrada antes de scrapear (evitar SSRF a redes internas).
- Tests pasando antes de cualquier push a `main`.

### Ask first (preguntar antes)
- Añadir dependencias pesadas (headless browser, libs grandes).
- Cambiar el contrato de API (`docs/API.md`) — romper cliente.
- Introducir P2P, pago o auth (fase 2, fuera de v1).

### Never (nunca)
- Hardcodear el dominio/credenciales del sitio origen en código fuente (config/env).
- Distribuir audio con copyright fuera del uso personal/archival previsto.
- Hacer scrape agresivo sin throttle (riesgo de ban / abuso del origen).

### Riesgo conocido (legal)
El audio scrapeado puede tener copyright y el scraping puede violar ToS del sitio origen
según jurisdicción. Alcance de uso previsto: **personal / archival**, self-host. El autor
asume la responsabilidad de uso. El seeding P2P (fase 2) amplifica este riesgo y se evaluará
explícitamente antes de implementarse.
```
