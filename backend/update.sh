#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

go build -o bin/vgradio-server ./cmd/server
launchctl kickstart -k "gui/$(id -u)/com.vgradio.server"
echo "vgradio-server actualizado y reiniciado."
