# VGRadio

Reproductor de música nativo macOS (SwiftUI) + backend scraper API (Go).

Pega la URL de un álbum → el backend lo scrapea async, cachea metadata + carátulas +
tracks `.mp3` → el cliente lo reproduce (stream o descarga offline). Ligero y bonito,
referencia *Tiny Player*.

> Uso **personal / archival**, self-host (Proxmox + Gitea + Drone CI).

## Estructura
```
backend/   API scraper en Go (goroutines, filesystem + SQLite)
VGRadio/   Cliente macOS SwiftUI (AVFoundation)
docs/      Contrato HTTP compartido (API.md)
SPEC.md    Spec maestro (SDD)
```

## Specs
- [SPEC.md](SPEC.md) — maestro
- [backend/SPEC.md](backend/SPEC.md)
- [VGRadio/SPEC.md](VGRadio/SPEC.md)
- [docs/API.md](docs/API.md)

## Estado
v1 (MVP) en desarrollo. P2P/seeding y pago = fase 2.

## Desarrollo
Spec-Driven Development → commit specs → TDD (tests unit safety net) → push a `main`.
