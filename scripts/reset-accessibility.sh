#!/bin/sh
set -eu

BUNDLE_ID="${1:-com.akis.WinPin}"

echo "Resetting Accessibility permission for ${BUNDLE_ID}"
tccutil reset Accessibility "${BUNDLE_ID}"
