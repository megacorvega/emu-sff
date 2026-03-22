#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

remove_user_crt_stack() {
    local desktop_home user_config_dir user_service_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    user_config_dir="${desktop_home}/.config/emu-sff"
    user_service_path="${desktop_home}/.config/systemd/user/emu-sff-crt-mode.service"

    if command -v runuser >/dev/null 2>&1; then
        runuser -u "${DESKTOP_USER}" -- systemctl --user disable --now emu-sff-crt-mode.service >/dev/null 2>&1 || true
        runuser -u "${DESKTOP_USER}" -- systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi

    rm -f "${user_service_path}"
    rm -rf "${user_config_dir}"
}

do_uninstall() {
    echo "======================================"
    echo "   emu-sff - Uninstall"
    echo "======================================"

    load_state_file || true
    read -r -p "Enter the config directory to remove [${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}]: " input_config_path
    CONFIG_PATH="${input_config_path:-${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}}"

    read -r -p "Are you sure you want to remove emu-sff generated config? [y/N]: " confirm_uninstall
    case "${confirm_uninstall}" in
        [yY]|[yY][eE][sS]) ;;
        *)
            print_warn "Uninstall cancelled."
            exit 0
            ;;
    esac

    if prompt_step "[1/5] Stop containers" "Stop and remove the generated Samba and dnsmasq containers."; then
        docker rm -f emu-samba emu-dhcp >/dev/null 2>&1 || true
    fi

    if prompt_step "[2/5] Remove LAN netplan config" "Delete /etc/netplan/99-emu-sff.yaml and re-apply Netplan."; then
        rm -f /etc/netplan/99-emu-sff.yaml
        netplan apply || true
    fi

    if prompt_step "[3/5] Restore Wi-Fi power saving" "Disable the persistent power-save override service."; then
        systemctl disable --now wifi-power-save-off.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/wifi-power-save-off.service
        systemctl daemon-reload
        if [[ -n "${WLAN_IF:-}" ]] && command -v iw >/dev/null 2>&1; then
            iw dev "${WLAN_IF}" set power_save on >/dev/null 2>&1 || true
        fi
    fi

    if prompt_step "[4/5] Remove CRT and RetroArch helper files" "Delete the generated xrandr script, launcher, and user service."; then
        if [[ -n "${DESKTOP_USER:-}" ]]; then
            remove_user_crt_stack
        fi
    fi

    if prompt_step "[5/5] Remove generated config directory" "Delete the generated Compose, Samba, dnsmasq, and state files in ${CONFIG_PATH}."; then
        if [[ -d "${CONFIG_PATH}" && "${CONFIG_PATH}" != "/" ]]; then
            rm -rf "${CONFIG_PATH}"
        fi
        rm -f "${EMU_SFF_STATE_FILE}"
    fi

    rm -f "${EMU_SFF_LAUNCHER_PATH}"
    rm -rf "${EMU_SFF_INSTALL_DIR}"

    print_info "Uninstall complete."
    pause_for_keypress "Press any key to return to the utility"
}
