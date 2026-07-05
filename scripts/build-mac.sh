#!/bin/bash
set -e

CONFIG="${1:-release}"
ROOT="/Users/maaya/dev/vgradio-app/VGRadio"
APP="/Applications/VGRadio.app/Contents/MacOS/VGRadio"

cd "$ROOT"
swift build -c "$CONFIG" || DEVELOPER_DIR=/Volumes/ExtDevDisk/Xcode.app/Contents/Developer swift build -c "$CONFIG"

pkill -x VGRadio 2>/dev/null || true
sleep 0.3

cp ".build/arm64-apple-macosx/$CONFIG/VGRadio" "$APP"
open /Applications/VGRadio.app
echo "OK: $CONFIG build deployed"
