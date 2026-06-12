# Tests — VGRadio Web

## Cómo correr

```bash
cd web

npm test              # unit tests (Vitest)
npm run test:watch    # unit tests en modo watch
npm run test:e2e      # E2E tests (Playwright, levanta dev server automático)
npm run test:e2e:ui   # E2E con UI interactiva de Playwright
```

---

## Unit Tests — Vitest (40 tests)

Framework: Vitest + jsdom. No requiere backend ni browser.
Setup: `src/test-setup.ts` mockea `localStorage` y `Audio`.

---

### `src/lib/utils.test.ts`

**`fmtTime`** — formatea segundos a `M:SS`

| Test | Qué verifica |
|------|-------------|
| formats zero | `fmtTime(0)` → `"0:00"` |
| formats seconds only | `fmtTime(45)` → `"0:45"` |
| formats minutes and seconds | `fmtTime(125)` → `"2:05"` |
| pads single-digit seconds | `fmtTime(61)` → `"1:01"` |
| handles large values | `fmtTime(3661)` → `"61:01"` |
| handles NaN | retorna `"0:00"` sin explotar |
| handles negative | retorna `"0:00"` sin explotar |
| truncates fractional seconds | `fmtTime(90.9)` → `"1:30"` |

**`timeAgo`** — tiempo relativo en español

| Test | Qué verifica |
|------|-------------|
| returns "ahora" for recent time | diff < 60s → `"ahora"` |
| returns minutes for older | diff ~5min → `"hace 5 min"` |
| returns hours for even older | diff ~3h → `"hace 3 h"` |
| returns days for ancient | diff ~2d → `"hace 2 d"` |

**`slugToTitle`** — slug de URL a título legible

| Test | Qué verifica |
|------|-------------|
| converts slug to title case | `super-mario-world` → `"Super Mario World"` |
| handles single word | `mario` → `"Mario"` |

**`letterGradient`** — gradiente CSS basado en título

| Test | Qué verifica |
|------|-------------|
| returns a CSS gradient string | comienza con `linear-gradient` y contiene `hsl(` |
| returns consistent output for same title | misma entrada → mismo resultado (determinista) |
| returns different output for different titles | entradas distintas → gradientes distintos |

---

### `src/lib/api.test.ts`

**`api.coverURL`** — construye URL de cover

| Test | Qué verifica |
|------|-------------|
| returns external URLs unchanged | URLs `https://` no se modifican |
| prepends backend base for relative paths | `/covers/...` → `http://HOST:8080/covers/...` |

**`api.streamURL / downloadURL`**

| Test | Qué verifica |
|------|-------------|
| prepends base URL to streamUrl | `track.streamUrl` recibe el prefijo del backend |

**`origURL regex`** — transformación de URL display → orig

| Test | Qué verifica |
|------|-------------|
| inserts _orig before extension for JPEG | `cover_0.jpg` → `cover_0_orig.jpg` |
| inserts _orig for PNG | `cover_3.png` → `cover_3_orig.png` |
| handles higher indices | `cover_12.jpg` → `cover_12_orig.jpg` |
| is idempotent on already-orig URLs | aplicar dos veces no produce `_orig_orig` |

---

### `src/lib/stores/favorites.test.ts`

**`favorites store`** — store de tracks favoritos con persistencia localStorage

| Test | Qué verifica |
|------|-------------|
| starts empty | store inicia con `[]` |
| toggle adds a track | `toggle(track, album)` agrega el track |
| toggle removes an existing track | doble toggle elimina el track |
| stores coverUrl from album | persiste `album.coverUrls[0]` en el FavoriteTrack |
| addAll adds all tracks, skipping duplicates | `addAll` no duplica si el track ya existe |
| removeAll removes by albumId | elimina todos los tracks de un álbum específico, preserva otros |

**`favoritesGrouped`** — derived store agrupado por álbum

| Test | Qué verifica |
|------|-------------|
| groups by albumId | tracks de álbumes distintos quedan en grupos separados |

---

### `src/lib/stores/hidden.test.ts`

**`hidden store`** — store de tracks ocultos (Set) con persistencia localStorage

| Test | Qué verifica |
|------|-------------|
| starts empty | store inicia con `Set` vacío |
| toggle adds an id | `toggle(id)` agrega el ID al Set |
| toggle removes an existing id | doble toggle elimina el ID |
| isHidden returns correct value | retorna `false` antes y `true` después del toggle |
| persists to localStorage | `localStorage["vgradio.hiddenTracks"]` contiene el ID oculto |

---

### `src/lib/stores/toasts.test.ts`

**`toasts store`** — notificaciones temporales con auto-dismiss

| Test | Qué verifica |
|------|-------------|
| addToast adds a toast | `addToast(msg, type)` agrega el toast con mensaje y tipo correctos |
| toast auto-dismisses after duration | después de `durationMs` el toast desaparece del store |
| multiple toasts are independent | el dismiss del primer toast no afecta al segundo |
| each toast gets a unique id | múltiples toasts tienen IDs distintos |

*Usa `vi.useFakeTimers()` para controlar el tiempo sin esperas reales.*

---

## E2E Tests — Playwright (10 tests)

Framework: Playwright + Chromium. El backend se mockea con `page.route()` — **no requiere backend corriendo**. El dev server de Vite se levanta automáticamente.

---

### `e2e/library.spec.ts`

Mock: `GET /albums` → 2 álbumes (Super Mario RPG, Chrono Trigger). `GET /history` → `[]`.

| Test | Qué verifica |
|------|-------------|
| library page loads and shows albums | los títulos de álbumes mockeados son visibles en la página |
| library shows album platform and year | plataforma ("SNES") y año ("1996") son visibles |
| library sidebar navigation links exist | el link de navegación "Library" existe en el sidebar |
| player bar is present | el player bar está presente en el DOM aunque no haya track cargado |

---

### `e2e/browse.spec.ts`

Mock: `GET /catalog/consoles` → NES + PlayStation. `GET /catalog?...` → 3 entradas filtradas por `q`. `GET /catalog/sync` → `{running: false}`.

| Test | Qué verifica |
|------|-------------|
| browse page shows catalog entries | las entradas del catálogo mockeado aparecen en la lista |
| browse search filters entries | escribir en el input filtra las entradas (con debounce 300ms) |
| browse shows console chips | los chips de consola (NES, PlayStation) son visibles |
| browse has letter strip from A to Z | los botones de letra A y Z existen en el strip |
| browse has sync button | el botón "Sync Catalog" está presente |
| clicking + button on entry triggers import | hover sobre entrada → click en `+` → POST a `/albums` → aparece checkmark `✓` |
