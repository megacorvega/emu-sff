#!/usr/bin/env bash

set -euo pipefail

CRT_SAFETY_PATH="__CRT_SAFETY_PATH__"
CRT_ARMED_VALUE="__CRT_ARMED_VALUE__"

if [[ ! -f "${CRT_SAFETY_PATH}" ]]; then
    echo "Missing CRT safety config: ${CRT_SAFETY_PATH}" >&2
    exit 1
fi

sed -i "s/^CRT_ARMED=.*/CRT_ARMED=${CRT_ARMED_VALUE}/" "${CRT_SAFETY_PATH}"

if [[ "${CRT_ARMED_VALUE}" == "1" ]]; then
    echo "CRT output armed in ${CRT_SAFETY_PATH}"
else
    echo "CRT output disarmed in ${CRT_SAFETY_PATH}"
fi
