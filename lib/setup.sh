#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

collect_setup_inputs() {
    local available_interfaces recommended_lan recommended_wlan default_desktop_user

    available_interfaces="$(ls /sys/class/net | grep -v '^lo$' | tr '\n' ' ' | sed 's/ $//')"
    recommended_lan="$(detect_first_interface '^en|^eth')"
    recommended_wlan="$(detect_first_interface '^wl|^wlan')"
    default_desktop_user="${SUDO_USER:-${USER}}"

    echo "Available network interfaces: ${available_interfaces}"

    read -r -p "Enter your LAN interface [${recommended_lan:-eth0}]: " LAN_IF
    LAN_IF="${LAN_IF:-${recommended_lan:-eth0}}"

    read -r -p "Enter your WLAN interface [${recommended_wlan:-wlan0}]: " WLAN_IF
    WLAN_IF="${WLAN_IF:-${recommended_wlan:-wlan0}}"

    read -r -p "Enter the absolute path for game storage [${DEFAULT_STORAGE_PATH}]: " STORAGE_PATH
    STORAGE_PATH="${STORAGE_PATH:-${DEFAULT_STORAGE_PATH}}"

    read -r -p "Enter the absolute path for generated config [${DEFAULT_CONFIG_PATH}]: " CONFIG_PATH
    CONFIG_PATH="${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}"

    read -r -p "Enter the desktop user that launches RetroArch [${default_desktop_user}]: " DESKTOP_USER
    DESKTOP_USER="${DESKTOP_USER:-${default_desktop_user}}"

    read -r -p "Enter the CRT display output name [${DEFAULT_DESKTOP_OUTPUT}]: " CRT_OUTPUT
    CRT_OUTPUT="${CRT_OUTPUT:-${DEFAULT_DESKTOP_OUTPUT}}"

    read -r -p "Enter the CRT super width [${DEFAULT_SUPER_WIDTH}]: " SUPER_WIDTH
    SUPER_WIDTH="${SUPER_WIDTH:-${DEFAULT_SUPER_WIDTH}}"

    read -r -p "Enter the CRT super height [${DEFAULT_SUPER_HEIGHT}]: " SUPER_HEIGHT
    SUPER_HEIGHT="${SUPER_HEIGHT:-${DEFAULT_SUPER_HEIGHT}}"

    SUPER_MODE_NAME="${SUPER_WIDTH}x${SUPER_HEIGHT}_60.00"
    read -r -p "Enter the xrandr mode name [${SUPER_MODE_NAME}]: " input_mode_name
    SUPER_MODE_NAME="${input_mode_name:-${SUPER_MODE_NAME}}"

    read -r -p "Enter the xrandr modeline [${DEFAULT_SUPER_MODELINE}]: " SUPER_MODELINE
    SUPER_MODELINE="${SUPER_MODELINE:-${DEFAULT_SUPER_MODELINE}}"
}

install_dependencies() {
    print_info "Installing Docker, RetroArch, and display tools."

    apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc >/dev/null 2>&1 || true
    apt-get update
    apt-get install -y ca-certificates curl gnupg wireless-tools x11-xserver-utils retroarch

    install -m 0755 -d /etc/apt/keyrings
    . /etc/os-release
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable
EOF

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

configure_networking() {
    print_info "Writing netplan config for ${LAN_IF}."

    cat > /etc/netplan/99-emu-sff.yaml <<EOF
network:
  version: 2
  ethernets:
    ${LAN_IF}:
      addresses: [192.168.2.1/24]
EOF

    netplan apply
}

configure_wifi_power_service() {
    print_info "Creating persistent Wi-Fi power-save override for ${WLAN_IF}."

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/wifi-power-save-off.service.tpl" \
        "/etc/systemd/system/wifi-power-save-off.service" \
        "WLAN_IF=${WLAN_IF}"

    systemctl daemon-reload
    systemctl enable --now wifi-power-save-off.service >/dev/null
}

generate_container_configs() {
    print_info "Generating dnsmasq, Samba, and Compose configuration."

    ensure_directory "${CONFIG_PATH}"
    ensure_directory "${CONFIG_PATH}/dnsmasq"
    ensure_directory "${CONFIG_PATH}/samba"
    ensure_directory "${STORAGE_PATH}" "0775"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/dnsmasq.conf.tpl" \
        "${CONFIG_PATH}/dnsmasq/dnsmasq.conf" \
        "LAN_IF=${LAN_IF}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/smb.conf.tpl" \
        "${CONFIG_PATH}/samba/smb.conf" \
        "STORAGE_PATH=${STORAGE_PATH}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/docker-compose.yml.tpl" \
        "${CONFIG_PATH}/docker-compose.yml" \
        "STORAGE_PATH=${STORAGE_PATH}" \
        "CONFIG_PATH=${CONFIG_PATH}"

    (cd "${CONFIG_PATH}" && docker compose up -d)
}

generate_crt_stack() {
    local desktop_home user_config_dir user_service_dir launcher_path crt_script_path safety_path arm_path disarm_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    if [[ -z "${desktop_home}" ]]; then
        print_error "Could not resolve home directory for desktop user ${DESKTOP_USER}."
        exit 1
    fi

    user_config_dir="${desktop_home}/.config/emu-sff"
    user_service_dir="${desktop_home}/.config/systemd/user"
    launcher_path="${user_config_dir}/launch-retroarch-crt.sh"
    crt_script_path="${user_config_dir}/apply-crt-mode.sh"
    safety_path="${user_config_dir}/crt-safety.conf"
    arm_path="${user_config_dir}/arm-crt-output.sh"
    disarm_path="${user_config_dir}/disarm-crt-output.sh"

    ensure_directory "${user_config_dir}"
    ensure_directory "${user_service_dir}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/crt-mode.sh.tpl" \
        "${crt_script_path}" \
        "CRT_OUTPUT=${CRT_OUTPUT}" \
        "SUPER_MODE_NAME=${SUPER_MODE_NAME}" \
        "SUPER_MODELINE=${SUPER_MODELINE}" \
        "CRT_SAFETY_PATH=${safety_path}"
    chmod 0755 "${crt_script_path}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/crt-safety.conf.tpl" \
        "${safety_path}" \
        "SUPER_MODE_NAME=${SUPER_MODE_NAME}" \
        "SUPER_MODELINE=${SUPER_MODELINE}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/crt-arm-toggle.sh.tpl" \
        "${arm_path}" \
        "CRT_SAFETY_PATH=${safety_path}" \
        "CRT_ARMED_VALUE=1"
    chmod 0755 "${arm_path}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/crt-arm-toggle.sh.tpl" \
        "${disarm_path}" \
        "CRT_SAFETY_PATH=${safety_path}" \
        "CRT_ARMED_VALUE=0"
    chmod 0755 "${disarm_path}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/retroarch-crt.cfg.tpl" \
        "${user_config_dir}/retroarch-crt.cfg" \
        "SUPER_WIDTH=${SUPER_WIDTH}" \
        "SUPER_HEIGHT=${SUPER_HEIGHT}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/retroarch-launcher.sh.tpl" \
        "${launcher_path}" \
        "CRT_SCRIPT_PATH=${crt_script_path}" \
        "RETROARCH_CONFIG_PATH=${user_config_dir}/retroarch-crt.cfg" \
        "CRT_SAFETY_PATH=${safety_path}"
    chmod 0755 "${launcher_path}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/retroarch-crt-setup.service.tpl" \
        "${user_service_dir}/emu-sff-crt-mode.service" \
        "CRT_SCRIPT_PATH=${crt_script_path}"

    chown -R "${DESKTOP_USER}:${DESKTOP_USER}" "${user_config_dir}" "${user_service_dir}"

    if command -v runuser >/dev/null 2>&1; then
        if ! runuser -u "${DESKTOP_USER}" -- systemctl --user daemon-reload >/dev/null 2>&1; then
            print_warn "Skipped systemctl --user daemon-reload because ${DESKTOP_USER} does not have an active user bus yet."
            print_warn "This is normal on headless setup or before the desktop user logs in."
        fi
    fi

    print_warn "CRT mode auto-apply is not enabled by setup."
    print_warn "Arm the CRT path manually with ${arm_path} only after verifying the chain on a safe display."
    print_warn "The launcher and mode script will refuse to run while CRT_ARMED=0 in ${safety_path}."
}

install_cli_launcher() {
    print_info "Installing emu-sff command launcher."

    rm -rf "${EMU_SFF_INSTALL_DIR}"
    ensure_directory "${EMU_SFF_INSTALL_DIR}"
    cp -R "${EMU_SFF_ROOT}/lib" "${EMU_SFF_INSTALL_DIR}/lib"
    cp -R "${EMU_SFF_ROOT}/templates" "${EMU_SFF_INSTALL_DIR}/templates"
    install -m 0755 "${EMU_SFF_ROOT}/emu-sff.sh" "${EMU_SFF_INSTALL_DIR}/emu-sff.sh"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/emu-sff-launcher.sh.tpl" \
        "${EMU_SFF_LAUNCHER_PATH}" \
        "EMU_SFF_SCRIPT_PATH=${EMU_SFF_INSTALL_DIR}/emu-sff.sh"
    chmod 0755 "${EMU_SFF_LAUNCHER_PATH}"
}

do_setup() {
    echo "======================================"
    echo "   emu-sff - Modular Setup"
    echo "======================================"

    collect_setup_inputs
    ensure_directory "${CONFIG_PATH}"
    save_state_file

    if prompt_step "[1/6] Install dependencies" "Install Docker Engine, RetroArch, xrandr tooling, and Wi-Fi utilities."; then
        install_dependencies
    else
        print_warn "Skipping dependency installation."
    fi

    if prompt_step "[2/6] Configure static LAN IP" "Assign ${LAN_IF} to 192.168.2.1/24 via Netplan."; then
        configure_networking
    else
        print_warn "Skipping static IP configuration."
    fi

    if prompt_step "[3/6] Disable Wi-Fi power saving" "Create a systemd service that keeps ${WLAN_IF} in power_save off mode."; then
        configure_wifi_power_service
    else
        print_warn "Skipping Wi-Fi power configuration."
    fi

    if prompt_step "[4/6] Configure SMB/DHCP services" "Generate container config and start Samba plus dnsmasq."; then
        generate_container_configs
    else
        print_warn "Skipping Docker service configuration."
    fi

    if prompt_step "[5/6] Configure CRT + RetroArch" "Generate a reusable 2560x240 super-resolution xrandr script, RetroArch config, launcher, and user service."; then
        generate_crt_stack
    else
        print_warn "Skipping CRT and RetroArch configuration."
    fi

    if prompt_step "[6/6] Install emu-sff command launcher" "Install /usr/local/bin/emu-sff so you can launch the utility from anywhere via sudo/systemd-run."; then
        install_cli_launcher
    else
        print_warn "Skipping command launcher installation."
    fi

    echo
    print_info "Setup complete. Running status check."
    do_status
}
