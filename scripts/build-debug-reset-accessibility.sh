#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "${ROOT_DIR}"
xcodebuild -project WinPin.xcodeproj -scheme WinPin -configuration Debug -derivedDataPath build/DerivedData build
scripts/reset-accessibility.sh
