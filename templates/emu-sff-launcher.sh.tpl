#!/usr/bin/env bash

set -euo pipefail

EMU_SFF_SCRIPT_PATH="__EMU_SFF_SCRIPT_PATH__"

if [[ ! -x "${EMU_SFF_SCRIPT_PATH}" ]]; then
    echo "emu-sff is not installed correctly: ${EMU_SFF_SCRIPT_PATH} is missing." >&2
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    if command -v systemd-run >/dev/null 2>&1; then
        exec systemd-run \
            --quiet \
            --collect \
            --wait \
            --pty \
            --same-dir \
            --service-type=exec \
            --unit="emu-sff-ui-$(date +%s)" \
            "${EMU_SFF_SCRIPT_PATH}" "$@"
    fi

    exec "${EMU_SFF_SCRIPT_PATH}" "$@"
fi

exec sudo "$0" "$@"
