#!/usr/bin/env bash
# Migra datos del backend local al homelab (192.168.0.104)
# Uso: bash scripts/migrate-to-homelab.sh

set -euo pipefail

SERVER="maaya@192.168.0.104"
CONTAINER="vgradio-backend"
LOCAL_DATA="$(dirname "$0")/../backend/data"
REMOTE_TMP="/tmp/vgradio-migrate"

echo "==> Checkpoint WAL en DB local..."
sqlite3 "$LOCAL_DATA/vgradio.db" "PRAGMA wal_checkpoint(TRUNCATE);"

echo "==> Copiando DB y archivos de audio al servidor..."
ssh "$SERVER" "mkdir -p $REMOTE_TMP"
scp "$LOCAL_DATA/vgradio.db" "$SERVER:$REMOTE_TMP/vgradio.db"

# Copiar archivos de audio (directorios de hash)
echo "==> Sincronizando archivos de audio (~$(du -sh "$LOCAL_DATA" | cut -f1))..."
rsync -avz --progress \
  --exclude "vgradio.db" \
  --exclude "vgradio.db-shm" \
  --exclude "vgradio.db-wal" \
  "$LOCAL_DATA/" "$SERVER:$REMOTE_TMP/audiofiles/"

echo "==> Deteniendo backend en homelab..."
ssh "$SERVER" "docker stop $CONTAINER 2>/dev/null || true"

echo "==> Copiando DB al volumen Docker..."
ssh "$SERVER" "
  docker run --rm \
    -v vgradio_vgradio-data:/data \
    -v $REMOTE_TMP:/src \
    alpine sh -c '
      cp /src/vgradio.db /data/vgradio.db
      cp -r /src/audiofiles/. /data/
      ls -lh /data/vgradio.db
      echo \"archivos copiados OK\"
    '
"

echo "==> Reiniciando backend..."
ssh "$SERVER" "docker start $CONTAINER"

echo "==> Verificando..."
sleep 2
curl -sk https://vgradio-api.lab/albums | python3 -c "
import sys, json
albums = json.load(sys.stdin)
print(f'OK — {len(albums)} albums migrados')
" 2>/dev/null || ssh "$SERVER" "curl -s http://localhost:8080/albums | python3 -c \"import sys,json; a=json.load(sys.stdin); print(f'OK — {len(a)} albums')\""

echo "==> Limpiando temporales..."
ssh "$SERVER" "rm -rf $REMOTE_TMP"

echo "DONE."
