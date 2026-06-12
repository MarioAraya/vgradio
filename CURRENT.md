# CURRENT — VGRadio

Última sesión: 2026-06-12

> Estado de implementación para retomar entre sesiones.
> Specs: `docs/SPEC-WEB.md`, `backend/SPEC.md`, `docs/API.md`.

---

## En progreso

### Cover carousel + lightbox — sin commitear

3 archivos modificados/nuevos:

- `web/src/lib/components/CoverCarousel.svelte` ← nuevo
- `web/src/lib/components/CoverLightbox.svelte` ← nuevo
- `web/src/routes/albums/[id]/+page.svelte` ← reemplaza bloque covers

**Qué hace:**
- `CoverCarousel`: wrapper 220px, swipe (pointer events, umbral 50px), botones `‹ ›` visibles solo on-hover, dots, click corto abre lightbox
- `CoverLightbox`: overlay fullscreen, sirve `cover_N_orig.ext` (sin comprimir), fallback a display si 404, nav ←/→/Escape, swipe, dots, cierra al click fuera

**No requiere cambios en backend** — `/covers/<albumId>/cover_N_orig.jpg` ya existe desde el commit `84ca80f`.

**Pendiente:** commitear estos 3 archivos.

---

## Completado esta sesión (sesión web-2)

- [x] **CoverCarousel.svelte** — swipe + hover arrows + click → lightbox
- [x] **CoverLightbox.svelte** — fullscreen modal, orig images, carousel, keyboard, swipe
- [x] **AlbumDetail actualizado** — reemplaza `<div class="covers">` + `CoverImage` por `CoverCarousel` + `CoverLightbox`
- [x] **CSS huérfano limpiado** — `.covers`, `.cover-dots`, `.dot` eliminados de `+page.svelte`

---

## Completado sesiones previas (web-1)

- [x] SvelteKit MVP completo con paridad de features al macOS client
- [x] Audio singleton, queue, repeat, shuffle, scrubber, volume
- [x] LAN access via `window.location.hostname` dinámico
- [x] Cover resize en scrape (display ≤400px) + ZIP download originals
- [x] `play_history` table con dedup, endpoints POST/GET `/history`
- [x] Browse/catalog con search, filtros, infinite scroll, sync polling
- [x] Favorites, wishlist, hidden, coverPrefs — localStorage
- [x] CORS middleware en Go backend

---

## Pendiente (próximos pasos)

- [ ] **Commitear** los 3 archivos de carousel/lightbox
- [ ] **Probar en browser** — verificar swipe en mobile, hover arrows en desktop, lightbox orig images
- [ ] **Recently played view** — sidebar link existe, vista pendiente
- [ ] **Settings view** — backend URL configurable desde UI (hoy solo via localStorage manual)
- [ ] **Tests** — cero tests en frontend web
- [ ] **Deploy VPS** — backend + frontend en servidor (Hetzner u otro)

---

## Notas

- Backend: `cd backend && go run ./cmd/server` (puerto 8080)
- Web dev: `cd web && npm run dev` (puerto 5173)
- LAN: frontend en `:5173` usa `window.location.hostname:8080` — funciona si se abre con IP del host, no localhost
- F5 mata el audio — limitación del browser, no fixeable. Spotify web igual. Navegar por SPA (click) no interrumpe.
- `cover_N_orig.ext` + `cover_N.ext` — backend guarda ambos en scrape. ZIP sirve orig. Display URL es el sin `_orig`.
- Orig URL derivación: `url.replace(/(cover_\d+)(\.[^.]+)$/, '$1_orig$2')` — en `CoverLightbox.svelte`
- Swift macOS client: rama `main`, build con Xcode en `/Volumes/ExtDevDisk/Xcode.app`
