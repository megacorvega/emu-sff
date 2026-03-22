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

status_value() {
    local state="$1"
    local detail="${2:-}"
    local color

    color="$(status_color "${state}")"

    case "${state}" in
        OK)
            printf '%bOK%b' "${color}" "${COLOR_RESET}${COLOR_TEXT}"
            ;;
        WARN)
            printf '%bWARN%b' "${color}" "${COLOR_RESET}${COLOR_TEXT}"
            ;;
        *)
            printf '%bERROR%b' "${color}" "${COLOR_RESET}${COLOR_TEXT}"
            ;;
    esac

    if [[ -n "${detail}" ]]; then
        printf ' - %s' "${detail}"
    fi
}

collect_status_rows() {
    local docker_state samba_state dhcp_state lan_state wifi_state retroarch_state
    local service_state armed_state detail

    if command_exists systemctl && systemctl is-active --quiet docker 2>/dev/null; then
        docker_state="OK"
    else
        docker_state="ERROR"
    fi

    if command_exists docker && check_docker_container "emu-samba"; then
        samba_state="OK"
    else
        samba_state="ERROR"
    fi

    if command_exists docker && check_docker_container "emu-dhcp"; then
        dhcp_state="OK"
    else
        dhcp_state="ERROR"
    fi

    if command_exists ip && ip addr show 2>/dev/null | grep -q '192.168.2.1/24'; then
        lan_state="OK"
        detail="192.168.2.1 configured"
    else
        lan_state="ERROR"
        detail="192.168.2.1 missing"
    fi
    printf 'Docker engine|%s|%s\n' "${docker_state}" ""
    printf 'Samba container|%s|%s\n' "${samba_state}" ""
    printf 'Dnsmasq container|%s|%s\n' "${dhcp_state}" ""
    printf 'Static LAN IP|%s|%s\n' "${lan_state}" "${detail}"

    if command_exists systemctl && systemctl is-active --quiet wifi-power-save-off.service 2>/dev/null; then
        wifi_state="OK"
        detail="power save disabled"
    else
        wifi_state="WARN"
        detail="service inactive"
    fi
    printf 'Wi-Fi override|%s|%s\n' "${wifi_state}" "${detail}"

    if command_exists "retroarch"; then
        retroarch_state="OK"
    else
        retroarch_state="ERROR"
    fi
    printf 'RetroArch binary|%s|%s\n' "${retroarch_state}" ""

    if [[ -n "${DESKTOP_USER:-}" ]] && check_user_service_file; then
        service_state="OK"
    else
        service_state="WARN"
    fi
    printf 'CRT user service|%s|%s\n' "${service_state}" ""

    if [[ -n "${DESKTOP_USER:-}" ]] && check_crt_armed; then
        armed_state="WARN"
        detail="output armed"
    else
        armed_state="OK"
        detail="output disarmed"
    fi
    printf 'CRT armed state|%s|%s\n' "${armed_state}" "${detail}"
}

render_status_screen() {
    local cpu_usage ram_usage storage_usage network_speed
    local row_index name state detail
    local line1 line2 line3 line4

    calculate_ui_layout

    cpu_usage="$(menu_cpu_usage)"
    ram_usage="$(menu_ram_usage)"
    storage_usage="$(menu_storage_usage)"
    network_speed="$(menu_network_speed)"
    line1="Desktop user: ${DESKTOP_USER:-n/a}"
    line2="CRT output: ${CRT_OUTPUT:-n/a}"
    line3="CRT mode: ${SUPER_MODE_NAME:-n/a}"
    line4="State file: ${EMU_SFF_STATE_FILE}"

    if (( UI_COMPACT_MODE == 1 )); then
        render_compact_box
        return 0
    fi

    printf "\033[2J\033[H"
    print_ui_margin
    printf "${COLOR_PANEL}${BOX_TOP_LEFT}%s${BOX_TOP_RIGHT}${COLOR_RESET}\n" "$(repeat_char "${BOX_HORIZONTAL}" $((UI_INNER_WIDTH + 2)))"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "status dashboard" "Live checks"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "" "Press any key to return"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "CPU: ${cpu_usage:-n/a}" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "RAM: ${ram_usage:-n/a}" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Disk: ${storage_usage:-n/a}" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Net: ${network_speed:-n/a}" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Service status" "Install context"

    row_index=0
    while IFS='|' read -r name state detail; do
        if (( row_index < 4 )); then
            case "${row_index}" in
                0) print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${name}: $(status_value "${state}" "${detail}")" "${line1}" ;;
                1) print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${name}: $(status_value "${state}" "${detail}")" "${line2}" ;;
                2) print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${name}: $(status_value "${state}" "${detail}")" "${line3}" ;;
                3) print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${name}: $(status_value "${state}" "${detail}")" "${line4}" ;;
            esac
        else
            print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${name}: $(status_value "${state}" "${detail}")" ""
        fi
        row_index=$((row_index + 1))
    done < <(collect_status_rows)

    print_ui_margin
    printf "${COLOR_PANEL}${BOX_BOTTOM_LEFT}%s${BOX_BOTTOM_RIGHT}${COLOR_RESET}\n" "$(repeat_char "${BOX_HORIZONTAL}" $((UI_INNER_WIDTH + 2)))"
}

do_status() {
    load_state_file || true
    render_status_screen

    pause_for_keypress
}
