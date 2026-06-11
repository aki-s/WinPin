#!/bin/sh
set -eu

LOG_PATH="${HOME}/Library/Logs/WinPin/app.log"

if ! [ -f "${LOG_PATH}" ]; then
    echo "No WinPin log found at ${LOG_PATH}" >&2
    touch "${LOG_PATH}"
fi

wc "${LOG_PATH}"
tail -f "${LOG_PATH}"

