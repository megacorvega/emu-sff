#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_docker_container() {
    local container_name="$1"
    docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null | grep -q '^true$'
}

check_user_service_file() {
    local desktop_home service_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    service_path="${desktop_home}/.config/systemd/user/emu-sff-crt-mode.service"
    [[ -f "${service_path}" ]]
}

check_crt_armed() {
    local desktop_home safety_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    safety_path="${desktop_home}/.config/emu-sff/crt-safety.conf"
    [[ -f "${safety_path}" ]] && grep -q '^CRT_ARMED=1$' "${safety_path}"
}

do_status() {
    load_state_file || true

    echo -e "\e[32m"
    cat <<'EOF'
 _____ __  __ _   _         ____  _____ _____
| ____|  \/  | | | |       / ___||  ___|  ___|
|  _| | |\/| | | | |  ___  \___ \| |_  | |_
| |___| |  | | |_| | |___|  ___) |  _| |  _|
|_____|_|  |_|\___/        |____/|_|   |_|
EOF
    echo -e "\e[0m"

    if systemctl is-active --quiet docker; then
        print_status "Docker Engine:           " "OK"
    else
        print_status "Docker Engine:           " "ERROR"
    fi

    if check_docker_container "emu-samba"; then
        print_status "Samba container:         " "OK"
    else
        print_status "Samba container:         " "ERROR"
    fi

    if check_docker_container "emu-dhcp"; then
        print_status "Dnsmasq container:       " "OK"
    else
        print_status "Dnsmasq container:       " "ERROR"
    fi

    if ip addr show | grep -q '192.168.2.1/24'; then
        print_status "Static LAN IP:           " "OK"
    else
        print_status "Static LAN IP:           " "ERROR"
    fi

    if systemctl is-active --quiet wifi-power-save-off.service; then
        print_status "Wi-Fi power override:    " "OK"
    else
        print_status "Wi-Fi power override:    " "WARN"
    fi

    if command -v retroarch >/dev/null 2>&1; then
        print_status "RetroArch binary:        " "OK"
    else
        print_status "RetroArch binary:        " "ERROR"
    fi

    if [[ -n "${DESKTOP_USER:-}" ]] && check_user_service_file; then
        print_status "CRT user service file:   " "OK"
    else
        print_status "CRT user service file:   " "WARN"
    fi

    if [[ -n "${DESKTOP_USER:-}" ]] && check_crt_armed; then
        print_status "CRT output armed:        " "WARN"
    else
        print_status "CRT output armed:        " "OK"
    fi

    if [[ -n "${DESKTOP_USER:-}" ]]; then
        local desktop_home crt_script launcher_path retroarch_cfg safety_cfg arm_script disarm_script
        desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
        crt_script="${desktop_home}/.config/emu-sff/apply-crt-mode.sh"
        launcher_path="${desktop_home}/.config/emu-sff/launch-retroarch-crt.sh"
        retroarch_cfg="${desktop_home}/.config/emu-sff/retroarch-crt.cfg"
        safety_cfg="${desktop_home}/.config/emu-sff/crt-safety.conf"
        arm_script="${desktop_home}/.config/emu-sff/arm-crt-output.sh"
        disarm_script="${desktop_home}/.config/emu-sff/disarm-crt-output.sh"

        [[ -f "${crt_script}" ]] && print_status "CRT mode script:         " "OK" || print_status "CRT mode script:         " "WARN"
        [[ -f "${launcher_path}" ]] && print_status "RetroArch launcher:      " "OK" || print_status "RetroArch launcher:      " "WARN"
        [[ -f "${retroarch_cfg}" ]] && print_status "RetroArch CRT config:    " "OK" || print_status "RetroArch CRT config:    " "WARN"
        [[ -f "${safety_cfg}" ]] && print_status "CRT safety config:       " "OK" || print_status "CRT safety config:       " "WARN"
        [[ -f "${arm_script}" ]] && print_status "CRT arm helper:          " "OK" || print_status "CRT arm helper:          " "WARN"
        [[ -f "${disarm_script}" ]] && print_status "CRT disarm helper:       " "OK" || print_status "CRT disarm helper:       " "WARN"
    fi

    if [[ -n "${CRT_OUTPUT:-}" ]]; then
        echo "CRT output target: ${CRT_OUTPUT}"
    fi
    if [[ -n "${SUPER_MODE_NAME:-}" ]]; then
        echo "CRT mode target: ${SUPER_MODE_NAME}"
    fi
}
