#!/usr/bin/env bash

set -euo pipefail

CRT_SAFETY_PATH="__CRT_SAFETY_PATH__"

if [[ ! -f "${CRT_SAFETY_PATH}" ]]; then
    echo "Missing CRT safety config: ${CRT_SAFETY_PATH}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CRT_SAFETY_PATH}"

if [[ "${CRT_ARMED:-0}" != "1" ]]; then
    echo "CRT output is disarmed. Refusing to launch RetroArch." >&2
    echo "Use the generated arm helper only after verifying your display chain is ready for 15 kHz." >&2
    exit 1
fi

"__CRT_SCRIPT_PATH__"
exec retroarch --config "__RETROARCH_CONFIG_PATH__" "$@"
