#!/usr/bin/env bash

set -euo pipefail

CRT_OUTPUT="__CRT_OUTPUT__"
MODE_NAME="__SUPER_MODE_NAME__"
MODELINE="__SUPER_MODELINE__"
CRT_SAFETY_PATH="__CRT_SAFETY_PATH__"

if [[ ! -f "${CRT_SAFETY_PATH}" ]]; then
    echo "Missing CRT safety config: ${CRT_SAFETY_PATH}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CRT_SAFETY_PATH}"

if ! command -v xrandr >/dev/null 2>&1; then
    echo "xrandr is required to apply CRT mode." >&2
    exit 1
fi

if [[ "${CRT_ARMED:-0}" != "1" ]]; then
    echo "CRT output is disarmed. Refusing to touch ${CRT_OUTPUT}." >&2
    echo "Review ${CRT_SAFETY_PATH}, then run the generated arm helper before use." >&2
    exit 1
fi

read -r HORIZONTAL_KHZ VERTICAL_HZ < <(
    awk '
        BEGIN {
            pixel_clock_mhz = $1
            h_total = $5
            v_total = $9
            h_khz = (pixel_clock_mhz * 1000) / h_total
            v_hz = (pixel_clock_mhz * 1000000) / (h_total * v_total)
            printf "%.3f %.3f\n", h_khz, v_hz
        }
    ' <<< "${MODELINE}"
)

awk -v h="${HORIZONTAL_KHZ}" \
    -v v="${VERTICAL_HZ}" \
    -v min_h="${MIN_HORIZONTAL_KHZ}" \
    -v max_h="${MAX_HORIZONTAL_KHZ}" \
    -v min_v="${MIN_VERTICAL_HZ}" \
    -v max_v="${MAX_VERTICAL_HZ}" '
    BEGIN {
        if (h < min_h || h > max_h || v < min_v || v > max_v) {
            exit 1
        }
    }
' || {
    echo "Refusing to apply mode ${MODE_NAME}." >&2
    echo "Computed sync is ${HORIZONTAL_KHZ} kHz / ${VERTICAL_HZ} Hz, outside the allowed CRT window." >&2
    exit 1
}

# Keep the mode application idempotent so the launcher and the user service can
# both call this script safely.
if ! xrandr | grep -Eq "^[[:space:]]+${MODE_NAME}([[:space:]]|$)"; then
    xrandr --newmode "${MODE_NAME}" ${MODELINE}
fi

xrandr --addmode "${CRT_OUTPUT}" "${MODE_NAME}" >/dev/null 2>&1 || true

xrandr --output "${CRT_OUTPUT}" --mode "${MODE_NAME}" --rate 60

if ! xrandr | grep -A20 "^${CRT_OUTPUT} " | grep -Eq "^[[:space:]]+${MODE_NAME}([[:space:]]|$).*\*"; then
    echo "xrandr did not report ${MODE_NAME} as the active mode on ${CRT_OUTPUT}." >&2
    exit 1
fi
