#!/usr/bin/env bash

set -euo pipefail

CRT_SAFETY_PATH="__CRT_SAFETY_PATH__"
VIDEO_OUTPUT_MODE="__VIDEO_OUTPUT_MODE__"
RETROARCH_CONFIG_PATH="__RETROARCH_CONFIG_PATH__"
RETROARCH_TTY_CONFIG_PATH="__RETROARCH_TTY_CONFIG_PATH__"

if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" && ! -f "${CRT_SAFETY_PATH}" ]]; then
    echo "Missing CRT safety config: ${CRT_SAFETY_PATH}" >&2
    exit 1
fi

# shellcheck disable=SC1090
if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" ]]; then
    source "${CRT_SAFETY_PATH}"
fi

if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" && "${CRT_ARMED:-0}" != "1" ]]; then
    echo "CRT output is disarmed. Refusing to launch RetroArch." >&2
    echo "Use the generated arm helper only after verifying your display chain is ready for 15 kHz." >&2
    exit 1
fi

if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" ]]; then
    "__CRT_SCRIPT_PATH__"
fi

if [[ "${EMU_SFF_TTY:-0}" == "1" ]]; then
    RETROARCH_CONFIG_PATH="${RETROARCH_TTY_CONFIG_PATH}"
fi

exec retroarch --config "${RETROARCH_CONFIG_PATH}" "$@"
