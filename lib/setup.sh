#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

collect_installation_choices() {
    local requested_profile="${1:-}" default_profile default_backend input_choice

    default_profile="${SETUP_PROFILE:-full}"
    if [[ -n "${requested_profile}" ]]; then
        SETUP_PROFILE="${requested_profile}"
        print_info "Using ${SETUP_PROFILE} installation profile."
    else
        read -r -p "Installation profile: full workstation or PS2-only server [${default_profile}]: " input_choice
        SETUP_PROFILE="${input_choice:-${default_profile}}"
    fi
    case "${SETUP_PROFILE}" in
        full|workstation) SETUP_PROFILE="full" ;;
        ps2|server|ps2-only) SETUP_PROFILE="ps2" ;;
        *)
            print_error "Unknown installation profile: ${SETUP_PROFILE}. Use full or ps2."
            exit 1
            ;;
    esac

    default_backend="${SERVICE_BACKEND:-}"
    if [[ -z "${default_backend}" ]]; then
        if [[ "${SETUP_PROFILE}" == "ps2" ]]; then
            default_backend="native"
        else
            default_backend="docker"
        fi
    fi
    read -r -p "Samba/dnsmasq backend: native or docker [${default_backend}]: " input_choice
    SERVICE_BACKEND="${input_choice:-${default_backend}}"
    case "${SERVICE_BACKEND}" in
        native|local) SERVICE_BACKEND="native" ;;
        docker|container) SERVICE_BACKEND="docker" ;;
        *)
            print_error "Unknown service backend: ${SERVICE_BACKEND}. Use native or docker."
            exit 1
            ;;
    esac

    if [[ "${SETUP_PROFILE}" == "ps2" ]]; then
        OPL_ENABLED="1"
    else
        read -r -p "Enable PS2/OPL ISO folders and DHCP-only networking? [Y/n]: " input_choice
        case "${input_choice:-Y}" in
            [Yy]*) OPL_ENABLED="1" ;;
            [Nn]*) OPL_ENABLED="0" ;;
            *)
                print_error "Please answer yes or no for PS2/OPL support."
                exit 1
                ;;
        esac
    fi
}

collect_setup_inputs() {
    local available_interfaces recommended_lan recommended_wlan default_desktop_user
    local input_storage_path input_config_path input_crt_output input_super_width input_super_height input_mode_name input_modeline

    available_interfaces="$(ls /sys/class/net | grep -v '^lo$' | tr '\n' ' ' | sed 's/ $//')"
    recommended_lan="$(detect_first_interface '^en|^eth')"
    recommended_wlan="$(detect_first_interface '^wl|^wlan')"
    default_desktop_user="${SUDO_USER:-${USER}}"

    echo "Available network interfaces: ${available_interfaces}"

    recommended_lan="${LAN_IF:-${recommended_lan:-eth0}}"
    read -r -p "Enter your LAN interface [${recommended_lan}]: " LAN_IF
    LAN_IF="${LAN_IF:-${recommended_lan}}"

    recommended_wlan="${WLAN_IF:-${recommended_wlan:-wlan0}}"
    read -r -p "Enter your WLAN interface [${recommended_wlan}]: " WLAN_IF
    WLAN_IF="${WLAN_IF:-${recommended_wlan}}"

    read -r -p "Enter the absolute path for game storage [${STORAGE_PATH:-${DEFAULT_STORAGE_PATH}}]: " input_storage_path
    STORAGE_PATH="${input_storage_path:-${STORAGE_PATH:-${DEFAULT_STORAGE_PATH}}}"

    read -r -p "Enter the absolute path for generated config [${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}]: " input_config_path
    CONFIG_PATH="${input_config_path:-${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}}"

    default_desktop_user="${DESKTOP_USER:-${default_desktop_user}}"
    read -r -p "Enter the desktop user that launches RetroArch [${default_desktop_user}]: " DESKTOP_USER
    DESKTOP_USER="${DESKTOP_USER:-${default_desktop_user}}"

    read -r -p "Enter the CRT display output name [${CRT_OUTPUT:-${DEFAULT_DESKTOP_OUTPUT}}]: " input_crt_output
    CRT_OUTPUT="${input_crt_output:-${CRT_OUTPUT:-${DEFAULT_DESKTOP_OUTPUT}}}"

    read -r -p "Enter the CRT super width [${SUPER_WIDTH:-${DEFAULT_SUPER_WIDTH}}]: " input_super_width
    SUPER_WIDTH="${input_super_width:-${SUPER_WIDTH:-${DEFAULT_SUPER_WIDTH}}}"

    read -r -p "Enter the CRT super height [${SUPER_HEIGHT:-${DEFAULT_SUPER_HEIGHT}}]: " input_super_height
    SUPER_HEIGHT="${input_super_height:-${SUPER_HEIGHT:-${DEFAULT_SUPER_HEIGHT}}}"

    SUPER_MODE_NAME="${SUPER_MODE_NAME:-${SUPER_WIDTH}x${SUPER_HEIGHT}_60.00}"
    read -r -p "Enter the xrandr mode name [${SUPER_MODE_NAME}]: " input_mode_name
    SUPER_MODE_NAME="${input_mode_name:-${SUPER_MODE_NAME}}"

    read -r -p "Enter the xrandr modeline [${SUPER_MODELINE:-${DEFAULT_SUPER_MODELINE}}]: " input_modeline
    SUPER_MODELINE="${input_modeline:-${SUPER_MODELINE:-${DEFAULT_SUPER_MODELINE}}}"
}

collect_ps2_setup_inputs() {
    local available_interfaces recommended_lan input_storage_path input_config_path

    available_interfaces="$(ls /sys/class/net | grep -v '^lo$' | tr '\n' ' ' | sed 's/ $//')"
    recommended_lan="$(detect_first_interface '^en|^eth')"

    echo "Available network interfaces: ${available_interfaces}"
    recommended_lan="${LAN_IF:-${recommended_lan:-eth0}}"
    read -r -p "Enter the Ethernet interface connected to the PS2 [${recommended_lan}]: " LAN_IF
    LAN_IF="${LAN_IF:-${recommended_lan}}"
    read -r -p "Enter the absolute path for PS2 game storage [${STORAGE_PATH:-${DEFAULT_STORAGE_PATH}}]: " input_storage_path
    STORAGE_PATH="${input_storage_path:-${STORAGE_PATH:-${DEFAULT_STORAGE_PATH}}}"
    read -r -p "Enter the absolute path for generated config [${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}]: " input_config_path
    CONFIG_PATH="${input_config_path:-${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}}"

    # Preserve any workstation metadata from an earlier full profile so a later
    # upgrade or uninstall can still find and manage those generated files.
    WLAN_IF="${WLAN_IF:-}"
    DESKTOP_USER="${DESKTOP_USER:-}"
    CRT_OUTPUT="${CRT_OUTPUT:-}"
    SUPER_WIDTH="${SUPER_WIDTH:-}"
    SUPER_HEIGHT="${SUPER_HEIGHT:-}"
    SUPER_MODE_NAME="${SUPER_MODE_NAME:-}"
    SUPER_MODELINE="${SUPER_MODELINE:-}"
}

install_dependencies() {
    print_info "Installing dependencies for the ${SETUP_PROFILE} profile with the ${SERVICE_BACKEND} service backend."

    apt-get update
    if [[ "${SETUP_PROFILE}" == "full" ]]; then
        apt-get install -y wireless-tools x11-xserver-utils retroarch
    fi

    if [[ "${SERVICE_BACKEND}" == "native" ]]; then
        apt-get install -y samba dnsmasq
        return
    fi

    apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc >/dev/null 2>&1 || true
    apt-get install -y ca-certificates curl gnupg

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
    local dnsmasq_template

    print_info "Generating Docker dnsmasq, Samba, and Compose configuration."

    ensure_directory "${CONFIG_PATH}"
    ensure_directory "${CONFIG_PATH}/dnsmasq"
    ensure_directory "${CONFIG_PATH}/samba"
    ensure_directory "${STORAGE_PATH}" "0775"
    if [[ "${OPL_ENABLED}" == "1" ]]; then
        ensure_directory "${STORAGE_PATH}/DVD" "0775"
        ensure_directory "${STORAGE_PATH}/CD" "0775"
        dnsmasq_template="${EMU_SFF_TEMPLATES_DIR}/ps2-dnsmasq.conf.tpl"
    else
        dnsmasq_template="${EMU_SFF_TEMPLATES_DIR}/dnsmasq.conf.tpl"
    fi

    render_template \
        "${dnsmasq_template}" \
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

configure_native_services() {
    local samba_backup_path dnsmasq_template

    print_info "Configuring native Samba and dnsmasq services."
    ensure_directory "${CONFIG_PATH}"
    ensure_directory "${CONFIG_PATH}/dnsmasq"
    ensure_directory "${CONFIG_PATH}/samba"
    ensure_directory "${STORAGE_PATH}" "0775"
    if [[ "${OPL_ENABLED}" == "1" ]]; then
        ensure_directory "${STORAGE_PATH}/DVD" "0775"
        ensure_directory "${STORAGE_PATH}/CD" "0775"
        dnsmasq_template="${EMU_SFF_TEMPLATES_DIR}/ps2-dnsmasq.conf.tpl"
    else
        dnsmasq_template="${EMU_SFF_TEMPLATES_DIR}/dnsmasq.conf.tpl"
    fi

    render_template "${dnsmasq_template}" "${CONFIG_PATH}/dnsmasq/dnsmasq.conf" "LAN_IF=${LAN_IF}"
    render_template "${EMU_SFF_TEMPLATES_DIR}/smb.conf.tpl" "${CONFIG_PATH}/samba/smb.conf" "STORAGE_PATH=${STORAGE_PATH}"

    samba_backup_path="/etc/samba/smb.conf.emu-sff-backup"
    if [[ -f /etc/samba/smb.conf && ! -f "${samba_backup_path}" ]]; then
        cp /etc/samba/smb.conf "${samba_backup_path}"
    fi
    install -m 0644 "${CONFIG_PATH}/samba/smb.conf" /etc/samba/smb.conf
    install -m 0644 "${CONFIG_PATH}/dnsmasq/dnsmasq.conf" /etc/dnsmasq.d/emu-sff-ps2.conf

    systemctl enable --now smbd.service
    systemctl restart smbd.service
    systemctl enable --now dnsmasq.service
    systemctl restart dnsmasq.service
}

remove_docker_services() {
    if command_exists docker; then
        docker rm -f emu-samba emu-dhcp >/dev/null 2>&1 || true
    fi
}

remove_native_service_configuration() {
    local managed_native=0

    if [[ -f /etc/dnsmasq.d/emu-sff-ps2.conf ]] || \
       [[ -f /etc/samba/smb.conf.emu-sff-backup ]]; then
        managed_native=1
    fi
    if (( managed_native == 0 )); then
        return
    fi

    systemctl disable --now smbd.service dnsmasq.service >/dev/null 2>&1 || true
    rm -f /etc/dnsmasq.d/emu-sff-ps2.conf
    if [[ -f /etc/samba/smb.conf.emu-sff-backup ]]; then
        mv /etc/samba/smb.conf.emu-sff-backup /etc/samba/smb.conf
    fi
}

configure_selected_services() {
    if [[ "${SERVICE_BACKEND}" == "docker" ]]; then
        remove_native_service_configuration
        generate_container_configs
    else
        remove_docker_services
        configure_native_services
    fi
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

do_refresh() {
    print_info "Refreshing emu-sff command launcher."
    install_cli_launcher
    print_info "Launcher refresh complete."

    if [[ -t 0 ]]; then
        pause_for_keypress "Press any key to return"
    fi
}

do_setup() {
    local requested_profile="${1:-}" previous_opl_enabled="" service_description

    echo "======================================"
    echo "   emu-sff - Setup"
    echo "======================================"

    PREVIOUS_SETUP_PROFILE=""
    PREVIOUS_SERVICE_BACKEND=""
    if load_state_file; then
        PREVIOUS_SETUP_PROFILE="${SETUP_PROFILE}"
        PREVIOUS_SERVICE_BACKEND="${SERVICE_BACKEND}"
        previous_opl_enabled="${OPL_ENABLED}"
        print_info "Found existing ${PREVIOUS_SETUP_PROFILE} installation using ${PREVIOUS_SERVICE_BACKEND} services."
    fi

    collect_installation_choices "${requested_profile}"
    if [[ "${SETUP_PROFILE}" == "full" ]]; then
        collect_setup_inputs
    else
        echo "This profile configures an isolated Ethernet link at 192.168.2.1/24."
        echo "Connect the selected interface only to the PS2/network adapter."
        collect_ps2_setup_inputs
    fi
    ensure_directory "${CONFIG_PATH}"

    if prompt_step "[Dependencies] Install required packages" "Install packages for the ${SETUP_PROFILE} profile and ${SERVICE_BACKEND} service backend."; then
        install_dependencies
    else
        print_warn "Skipping dependency installation. Required packages must already be installed."
    fi

    if prompt_step "[Networking] Configure static LAN IP" "Assign ${LAN_IF} to 192.168.2.1/24 via Netplan."; then
        configure_networking
    else
        print_warn "Skipping static IP configuration."
    fi

    if [[ "${SETUP_PROFILE}" == "full" ]]; then
        if prompt_step "[Wi-Fi] Disable Wi-Fi power saving" "Create a systemd service that keeps ${WLAN_IF} in power_save off mode."; then
            configure_wifi_power_service
        else
            print_warn "Skipping Wi-Fi power configuration."
        fi
    fi

    service_description="Configure Samba and dnsmasq using the ${SERVICE_BACKEND} backend."
    if [[ -n "${PREVIOUS_SERVICE_BACKEND}" && "${PREVIOUS_SERVICE_BACKEND}" != "${SERVICE_BACKEND}" ]]; then
        service_description+=" The existing ${PREVIOUS_SERVICE_BACKEND} backend will be removed first."
    fi
    if prompt_step "[File server] Configure SMB/DHCP services" "${service_description}"; then
        # Persist the selected backend before migration so status/uninstall reflect
        # the intended owner even if the new service fails to start.
        save_state_file
        configure_selected_services
    else
        print_warn "Skipping service configuration."
        if [[ -n "${PREVIOUS_SERVICE_BACKEND}" ]]; then
            SERVICE_BACKEND="${PREVIOUS_SERVICE_BACKEND}"
            OPL_ENABLED="${previous_opl_enabled}"
            print_warn "Keeping persisted service state on the existing ${SERVICE_BACKEND} backend."
        fi
    fi

    if [[ "${SETUP_PROFILE}" == "full" ]]; then
        if prompt_step "[CRT] Configure CRT + RetroArch" "Generate a reusable 2560x240 super-resolution xrandr script, RetroArch config, launcher, and user service."; then
            generate_crt_stack
        else
            print_warn "Skipping CRT and RetroArch configuration."
        fi
    fi

    if prompt_step "[Launcher] Install emu-sff command launcher" "Install /usr/local/bin/emu-sff so you can launch the utility from anywhere via sudo/systemd-run."; then
        install_cli_launcher
    else
        print_warn "Skipping command launcher installation."
    fi

    save_state_file

    echo
    print_info "${SETUP_PROFILE} setup complete. Running status check."
    if [[ "${OPL_ENABLED}" == "1" ]]; then
        print_info "Store PS2 ISOs in ${STORAGE_PATH}/DVD or ${STORAGE_PATH}/CD. In OPL, use 192.168.2.1 and share name share."
    fi
    do_status
}

do_ps2_setup() {
    print_warn "The ps2 command is retained for compatibility and now opens the unified setup with the PS2-only profile."
    do_setup ps2
}
