#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${ROOT_DIR}/build/DerivedData/Build/Products/Debug/WinPin.app"

cd "${ROOT_DIR}"

pkill WinPin 2>/dev/null || true

if [ "${1:-}" = "--show-dock" ]; then
    open "${APP_PATH}" --args --show-dock
else
    open "${APP_PATH}"
fi
