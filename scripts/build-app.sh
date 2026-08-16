#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ARCH="${ARCH:-arm64}"
APP_VERSION="${APP_VERSION:-0.0.1}"

cd "${ROOT_DIR}"
make build-app ARCH="${ARCH}" APP_VERSION="${APP_VERSION}"
