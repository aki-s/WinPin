#!/bin/sh
set -eu

LOG_PATH="${HOME}/Library/Logs/WinPin/app.log"

if [ -f "${LOG_PATH}" ]; then
    cat "${LOG_PATH}"
else
    echo "No WinPin log found at ${LOG_PATH}" >&2
    exit 1
fi
