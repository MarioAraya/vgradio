# Deploy a Homelab — Guía para nuevos proyectos

Stack: **Gitea** (VCS) + **Drone CI** (pipeline) + **Docker Registry** + **Traefik** (reverse proxy) + **Docker Compose** (runtime)

Infraestructura en `192.168.0.103`, dominio wildcard `*.lab` con TLS mkcert.

---

## 1. Crear repo en Gitea

### Manual
Ir a `http://192.168.0.103:3000` y crear repo.

### Automático (script)
```bash
GITEA_TOKEN=<tu_token> bash ~/dev/1_Scripts/homelab\ deploy/create-gitea-repos.sh
```
El script lee `GITEA_TOKEN` del env. Genera un nuevo token en:
`http://192.168.0.103:3000/user/settings/applications`

Agregar remote al repo local:
```bash
git remote add gitea http://192.168.0.103:3000/maaya/<repo>.git
git push gitea main
```

---

## 2. Agregar remote de Gitea y activar en Drone

### Activar repo en Drone (API)
```bash
# Obtener token de Drone desde la DB del servidor
ssh maaya@192.168.0.103 \
  "sqlite3 /var/lib/docker/volumes/cicd_drone_data/_data/database.sqlite \
   'SELECT user_login, user_hash FROM users;'"

# Activar repo
curl -sk -X POST "https://drone.lab/api/repos/maaya/<repo>" \
  -H "Authorization: Bearer <drone_token>"
```

---

## 3. SSH key para deploy

Drone necesita una clave SSH para conectarse al servidor y ejecutar `docker compose`.

### Verificar si ya existe `drone_ci`
```bash
ssh maaya@192.168.0.103 "ls ~/.ssh/drone_ci*"
```

### Si no existe, crear:
```bash
ssh maaya@192.168.0.103 "ssh-keygen -t ed25519 -f ~/.ssh/drone_ci -N '' -C 'drone-ci'"
ssh maaya@192.168.0.103 "cat ~/.ssh/drone_ci.pub >> ~/.ssh/authorized_keys"
```

### Agregar secret `ssh_private_key` a Drone:
```bash
DRONE_TOKEN=<drone_token>
PRIVATE_KEY=$(ssh maaya@192.168.0.103 "cat ~/.ssh/drone_ci")

curl -sk -X POST "https://drone.lab/api/repos/maaya/<repo>/secrets" \
  -H "Authorization: Bearer $DRONE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"ssh_private_key\", \"data\": $(echo "$PRIVATE_KEY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'), \"pull_request\": false}"
```

---

## 4. Preparar servidor

```bash
ssh maaya@192.168.0.103 "mkdir -p ~/srv/<proyecto>"
scp docker-compose.yml maaya@192.168.0.103:~/srv/<proyecto>/
```

El deploy path en `.drone.yml` debe ser `~/srv/<proyecto>` (sin sudo).

---

## 5. Docker Registry

Registry local en `registry.lab` (HTTP, insecure).

Para que Docker en el servidor lo acepte, verificar en `/etc/docker/daemon.json`:
```json
{ "insecure-registries": ["registry.lab"] }
```

---

## 6. Traefik

Los contenedores se conectan a la red externa `traefik-net`. Labels mínimos:

```yaml
networks:
  traefik-net:
    external: true

services:
  myapp:
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.lab`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=<port>"
```

---

## 7. .drone.yml — template mínimo

```yaml
kind: pipeline
type: docker
name: ci-deploy

trigger:
  branch:
    - main

steps:
  - name: build-image
    image: plugins/docker
    settings:
      registry: registry.lab
      repo: registry.lab/maaya/<proyecto>
      tags: ["latest", "${DRONE_COMMIT_SHA:0:7}"]
      context: .
      dockerfile: Dockerfile
      insecure: true
      build_args:
        - SOME_ARG=value

  - name: deploy
    image: appleboy/drone-ssh
    settings:
      host: 192.168.0.103
      username: maaya
      key:
        from_secret: ssh_private_key
      script:
        - cd ~/srv/<proyecto>
        - docker compose pull
        - docker compose up -d --remove-orphans
    when:
      status:
        - success
```

---

## 8. Checklist para nuevo proyecto

- [ ] Crear repo en Gitea (script o manual)
- [ ] `git remote add gitea http://192.168.0.103:3000/maaya/<repo>.git`
- [ ] Activar repo en Drone (API o UI en `https://drone.lab`)
- [ ] Agregar secret `ssh_private_key` al repo en Drone (ver paso 3)
- [ ] `mkdir -p ~/srv/<proyecto>` en servidor + copiar `docker-compose.yml`
- [ ] Escribir `Dockerfile` + `.drone.yml` en el repo
- [ ] `git push gitea main` → pipeline dispara automáticamente

---

## Tokens y accesos

| Servicio  | URL                               | Cómo obtener token |
|-----------|-----------------------------------|--------------------|
| Gitea     | `http://192.168.0.103:3000`       | Settings → Applications |
| Drone     | `https://drone.lab`               | `sqlite3` en servidor (ver paso 2) |
| Registry  | `registry.lab`                    | Sin auth (LAN only) |
