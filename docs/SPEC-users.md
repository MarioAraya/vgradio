# SPEC — Multi-usuario (Fase 2)

> Rama: `users` | Estado: draft | Fecha: 2026-06-14

---

## 1. Objetivo

Agregar soporte multi-usuario a VGRadio web con acceso público parcial (lazy auth).
El catálogo y los álbumes son **globales**. Solo favoritos, historial y (futuro) playlists son **per-user**.

### Problema
Actualmente toda la app asume single-user. No hay auth, todos los endpoints son públicos, `play_history` no tiene dueño.

### Solución
- Home público: cualquier visitante puede explorar álbumes y reproducir sin cuenta.
- Lazy auth: cuando el usuario intenta una **acción que persiste datos** (guardar favorito, etc.), se muestra modal de login. Si ya tiene sesión, la acción procede directamente.
- Registro con `email + username + password`.
- Session cookie server-side (sin JWT). Simple, stateful, SQLite-backed.
- Username visible en la UI (esquina del header).
- Password reset manual vía ruta admin protegida por `ADMIN_SECRET` env var.

---

## 2. Usuarios objetivo

- Uso personal + allegados del autor (decenas de usuarios, no miles).
- Self-host en homelab.

---

## 3. Features y criterios de aceptación

### 3.1 Acceso público (sin cuenta)

| Feature | Criterio de aceptación |
|---|---|
| Navegar catálogo | `GET /catalog`, `GET /browse` — funciona sin cookie |
| Ver álbum | `GET /albums/{id}` — funciona sin cookie |
| Reproducir track | `GET /tracks/{id}/stream` — funciona sin cookie |
| Historial | NO se guarda si no hay sesión activa |
| Favorito | Click en ★ sin sesión → abre modal login |

### 3.2 Registro

- Campos: `username` (único, 3-30 chars, alfanumérico + `-_`), `email` (único, válido), `password` (mín 8 chars).
- `POST /auth/register` → crea usuario, inicia sesión, devuelve Set-Cookie.
- Errores claros: "username ya en uso", "email ya en uso".

### 3.3 Login / Logout

- `POST /auth/login` con `email` + `password` → Set-Cookie `sid=<uuid>; HttpOnly; SameSite=Lax; Path=/`
- `POST /auth/logout` → invalida sesión en DB, borra cookie.
- Sesiones expiran en **30 días** (sliding — se renueva en cada request autenticado).

### 3.4 Lazy auth (UX clave)

- Modal de login/registro aparece **en overlay** cuando acción requiere cuenta.
- Tras autenticarse en el modal, la acción original **se ejecuta automáticamente**.
- No hay redirect. El usuario sigue en la misma página.
- Modal tiene tabs: "Iniciar sesión" / "Crear cuenta".

### 3.5 Favoritos

- `POST /favorites/{album_id}` — toggle (crea si no existe, elimina si existe).
- `GET /favorites` — lista álbumes favoritos del usuario autenticado.
- `GET /albums/{id}` y listados incluyen campo `isFavorite: bool` si hay sesión.
- Página `/favorites` muestra grid de álbumes favoritos.

### 3.6 Historial per-user

- `POST /history` solo persiste si hay sesión activa (antes persistía siempre).
- `GET /history` devuelve historial del usuario autenticado.
- Sin sesión: `GET /history` devuelve `[]`.

### 3.7 Username en UI

- Header del layout muestra username si hay sesión: `@maaya ▾` con dropdown (Ver perfil / Cerrar sesión).
- Sin sesión: botón "Entrar" que abre el modal lazy-auth.

### 3.8 Password reset (admin)

- `POST /admin/reset-password` protegido por `X-Admin-Key: $ADMIN_SECRET`.
- Body: `{ "email": "x@x.com", "password": "nueva" }`.
- Sin SMTP, sin emails. Admin lo corre manualmente.

---

## 4. Arquitectura

### 4.1 Backend — nuevas tablas SQL

```sql
-- Migración idempotente (ALTER TABLE IF NOT EXISTS no existe en SQLite;
-- usar patrón: intentar CREATE, ignorar error si existe)

CREATE TABLE IF NOT EXISTS users (
    id           TEXT PRIMARY KEY,           -- UUID v4
    username     TEXT NOT NULL UNIQUE,
    email        TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,             -- bcrypt cost 12
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS sessions (
    id         TEXT PRIMARY KEY,             -- UUID v4 (el valor de la cookie)
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS favorites (
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    album_id   TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    PRIMARY KEY (user_id, album_id)
);
```

**Migración play_history:**
```sql
-- Agregar user_id nullable (histórico sin dueño = NULL)
ALTER TABLE play_history ADD COLUMN user_id TEXT REFERENCES users(id) ON DELETE SET NULL;
```

### 4.2 Backend — nuevos endpoints

```
POST /auth/register          public
POST /auth/login             public
POST /auth/logout            autenticado
GET  /auth/me                autenticado → { id, username, email }

POST /favorites/{album_id}   autenticado (toggle)
GET  /favorites              autenticado

POST /admin/reset-password   X-Admin-Key header
```

### 4.3 Backend — middleware de auth

```go
// authMiddleware lee cookie "sid", busca en sessions, renueva expires_at,
// inyecta userID en context. Si no hay cookie o sesión expirada → continúa
// sin userID (acceso anónimo permitido).
//
// requireAuth wraps handlers que exigen sesión → 401 si no hay userID en ctx.
```

- `authMiddleware`: aplica a **todas** las rutas. Inyecta `userID` (puede ser vacío).
- `requireAuth`: wrapper adicional solo para rutas que lo necesitan.
- Rutas existentes (stream, catalog, albums): solo leen `userID` del ctx para enriquecer respuesta (`isFavorite`), no fallan si es vacío.

### 4.4 Frontend — nuevos componentes (SvelteKit)

```
src/
  lib/
    stores/
      auth.svelte.ts          # estado global: currentUser | null
    components/
      AuthModal.svelte        # modal login/register con tabs
      UserMenu.svelte         # dropdown header con username
      FavoriteButton.svelte   # ★ que dispara lazy-auth si no hay sesión
  routes/
    favorites/+page.svelte    # ya existe, convertir a per-user
    +layout.svelte            # agregar UserMenu al header
```

### 4.5 Flujo lazy auth

```
Usuario click ★
    │
    ├─ ¿hay currentUser? ──Sí──→ POST /favorites/{id} → actualiza UI
    │
    └─ No → abre AuthModal
                │
                └─ login/registro exitoso
                        │
                        └─ cierra modal → ejecuta acción original → actualiza UI
```

---

## 5. Cambios en endpoints existentes

| Endpoint | Cambio |
|---|---|
| `GET /albums` | Si hay sesión → incluir `isFavorite` por álbum |
| `GET /albums/{id}` | Si hay sesión → incluir `isFavorite` |
| `POST /history` | Si no hay sesión → no persistir (silently skip) |
| `GET /history` | Filtrar por `user_id` si hay sesión; sin sesión → `[]` |
| `GET /stats` | Sin cambios (stats globales) |

---

## 6. Seguridad

- Passwords: `bcrypt` cost 12. Nunca plaintext.
- Cookie: `HttpOnly`, `SameSite=Lax`. Sin `Secure` en dev local; con `Secure` en prod (detrás de nginx/TLS).
- `ADMIN_SECRET`: mín 32 chars, de env var. No hardcodeado.
- Rate limit en `POST /auth/login`: máx 10 intentos / IP / minuto (evitar brute force). Implementar con map en memoria + ticker de limpieza (sin deps externas).
- Validar y sanitizar `username` (allowlist chars), `email` (regex básico), `password` (longitud).
- Sessions: UUID v4 generado con `crypto/rand`. No predecible.

---

## 7. Estilo de código (extensión del SPEC maestro)

- Nuevo paquete `internal/auth` — lógica de hashing, validación, session management.
- Store methods nuevos en `internal/store`: `CreateUser`, `GetUserByEmail`, `CreateSession`, `GetSession`, `DeleteSession`, `RenewSession`, `ToggleFavorite`, `GetFavorites`, `IsFavorite`.
- Frontend: `auth.svelte.ts` usa Svelte 5 runes (`$state`, `$derived`). No Svelte stores legacy.
- Llamadas a `/auth/me` al montar el layout para hidratar `currentUser`.

---

## 8. Comandos

```bash
# Backend (sin cambios en el comando base)
cd backend && go run ./cmd/server

# Nueva env var requerida en dev
ADMIN_SECRET=dev-only-insecure-reset-key go run ./cmd/server

# Tests nuevos
go test ./internal/auth/...
go test ./internal/store/...     # ya existentes + nuevos casos auth
```

---

## 9. Fuera de alcance (esta iteración)

- Email de verificación de cuenta.
- OAuth / login social.
- Playlists (se deja preparada la base de usuarios para cuando se implemente).
- Roles/permisos (todos los usuarios tienen el mismo nivel).
- Perfil público de usuario.

---

## 10. Plan de tareas (orden de implementación)

1. **Backend — schema + store**: tablas `users`, `sessions`, `favorites`, migración `play_history`.
2. **Backend — paquete `auth`**: bcrypt helpers, UUID gen, validación de campos.
3. **Backend — endpoints auth**: `register`, `login`, `logout`, `me`.
4. **Backend — middleware**: `authMiddleware` + `requireAuth`.
5. **Backend — endpoints favorites**: toggle + lista.
6. **Backend — enrichment**: `isFavorite` en `/albums` y `/albums/{id}`; `user_id` en history.
7. **Backend — admin reset-password**.
8. **Frontend — `auth.svelte.ts`**: store + `/auth/me` al montar.
9. **Frontend — `AuthModal.svelte`**: tabs login/registro.
10. **Frontend — `UserMenu.svelte`**: header con username/dropdown/"Entrar".
11. **Frontend — `FavoriteButton.svelte`**: lazy auth trigger.
12. **Frontend — `/favorites` page**: per-user.
13. **Tests**: unit tests auth + store, integración middleware.

---

## 11. Boundaries

### Always
- Catálogo y streams accesibles sin cuenta.
- bcrypt para passwords, nunca MD5/SHA sin salt.
- Lazy auth: nunca redirigir, siempre modal en overlay.

### Ask first
- Agregar email SMTP (implica infra externa).
- Cambiar cookie a JWT (rompe simplicidad MVP).
- Agregar roles/admin web (scope creep).

### Never
- Guardar passwords en plaintext ni en logs.
- Hardcodear `ADMIN_SECRET`.
- Bloquear acceso a reproducción por falta de cuenta.
