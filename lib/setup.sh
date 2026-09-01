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
    local default_video_output input_storage_path input_config_path input_crt_output input_super_width input_super_height input_mode_name input_modeline
    local input_video_output input_tv_norm input_autostart

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

    default_video_output="${VIDEO_OUTPUT_MODE:-}"
    if [[ -z "${default_video_output}" ]]; then
        if [[ -r /proc/device-tree/model ]] && grep -q 'Raspberry Pi' /proc/device-tree/model; then
            default_video_output="rpi-composite"
        else
            default_video_output="${DEFAULT_VIDEO_OUTPUT_MODE}"
        fi
    fi
    read -r -p "Video output method: xrandr or rpi-composite [${default_video_output}]: " input_video_output
    VIDEO_OUTPUT_MODE="${input_video_output:-${default_video_output}}"
    case "${VIDEO_OUTPUT_MODE}" in
        xrandr) ;;
        rpi-composite|composite) VIDEO_OUTPUT_MODE="rpi-composite" ;;
        *)
            print_error "Unknown video output method: ${VIDEO_OUTPUT_MODE}. Use xrandr or rpi-composite."
            exit 1
            ;;
    esac

    if [[ "${VIDEO_OUTPUT_MODE}" == "rpi-composite" ]]; then
        read -r -p "Composite TV standard (NTSC, PAL, PAL60, etc.) [${COMPOSITE_TV_NORM:-${DEFAULT_COMPOSITE_TV_NORM}}]: " input_tv_norm
        COMPOSITE_TV_NORM="${input_tv_norm:-${COMPOSITE_TV_NORM:-${DEFAULT_COMPOSITE_TV_NORM}}}"
        case "${COMPOSITE_TV_NORM}" in
            NTSC|NTSC-J|NTSC-443|PAL|PAL-M|PAL-N|PAL60|SECAM) ;;
            *)
                print_error "Unsupported composite TV standard: ${COMPOSITE_TV_NORM}."
                exit 1
                ;;
        esac
    else
        COMPOSITE_TV_NORM="${COMPOSITE_TV_NORM:-${DEFAULT_COMPOSITE_TV_NORM}}"
    fi

    if [[ "${VIDEO_OUTPUT_MODE}" == "rpi-composite" ]]; then
        read -r -p "Start RetroArch automatically at desktop login? [Y/n]: " input_autostart
        input_autostart="${input_autostart:-Y}"
    else
        read -r -p "Start RetroArch automatically at desktop login? [y/N]: " input_autostart
        input_autostart="${input_autostart:-N}"
    fi
    case "${input_autostart}" in
        [Yy]*) RETROARCH_AUTOSTART="1" ;;
        [Nn]*) RETROARCH_AUTOSTART="0" ;;
        *)
            print_error "Please answer yes or no for RetroArch autostart."
            exit 1
            ;;
    esac

    if [[ "${VIDEO_OUTPUT_MODE}" == "rpi-composite" ]]; then
        CRT_OUTPUT="Composite-1"
        SUPER_WIDTH="720"
        case "${COMPOSITE_TV_NORM}" in
            PAL|PAL-N|SECAM) SUPER_HEIGHT="576" ;;
            *) SUPER_HEIGHT="480" ;;
        esac
        SUPER_MODE_NAME="composite-${COMPOSITE_TV_NORM}"
        SUPER_MODELINE=""
        return
    fi

    if [[ "${SUPER_MODE_NAME:-}" == composite-* ]]; then
        CRT_OUTPUT="${DEFAULT_DESKTOP_OUTPUT}"
        SUPER_WIDTH="${DEFAULT_SUPER_WIDTH}"
        SUPER_HEIGHT="${DEFAULT_SUPER_HEIGHT}"
        SUPER_MODE_NAME="${DEFAULT_SUPER_MODE_NAME}"
        SUPER_MODELINE="${DEFAULT_SUPER_MODELINE}"
    fi

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
    VIDEO_OUTPUT_MODE="${VIDEO_OUTPUT_MODE:-${DEFAULT_VIDEO_OUTPUT_MODE}}"
    COMPOSITE_TV_NORM="${COMPOSITE_TV_NORM:-${DEFAULT_COMPOSITE_TV_NORM}}"
    COMPOSITE_MARGIN_LEFT="${COMPOSITE_MARGIN_LEFT:-${DEFAULT_COMPOSITE_MARGIN_LEFT}}"
    COMPOSITE_MARGIN_RIGHT="${COMPOSITE_MARGIN_RIGHT:-${DEFAULT_COMPOSITE_MARGIN_RIGHT}}"
    COMPOSITE_MARGIN_TOP="${COMPOSITE_MARGIN_TOP:-${DEFAULT_COMPOSITE_MARGIN_TOP}}"
    COMPOSITE_MARGIN_BOTTOM="${COMPOSITE_MARGIN_BOTTOM:-${DEFAULT_COMPOSITE_MARGIN_BOTTOM}}"
    RETROARCH_AUTOSTART="${RETROARCH_AUTOSTART:-0}"
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

validate_composite_margin() {
    local name="$1" value="$2"

    if [[ ! "${value}" =~ ^[0-9]+$ ]] || (( 10#${value} > 200 )); then
        print_error "${name} margin must be a whole number from 0 through 200 (received: ${value})."
        return 1
    fi
}

composite_connector_name() {
    local connector_path connector_base

    for connector_path in /sys/class/drm/card*-Composite-* /sys/class/drm/card*-composite-*; do
        if [[ -e "${connector_path}" ]]; then
            connector_base="$(basename "${connector_path}")"
            printf '%s\n' "${connector_base#*-}"
            return 0
        fi
    done
    printf 'Composite-1\n'
}

apply_composite_margins() {
    local cmdline_path connector mode_spec

    if [[ -f /boot/firmware/cmdline.txt ]]; then
        cmdline_path="/boot/firmware/cmdline.txt"
    elif [[ -f /boot/cmdline.txt ]]; then
        cmdline_path="/boot/cmdline.txt"
    else
        print_error "Could not find the Raspberry Pi kernel command line."
        return 1
    fi

    validate_composite_margin "Left" "${COMPOSITE_MARGIN_LEFT}"
    validate_composite_margin "Right" "${COMPOSITE_MARGIN_RIGHT}"
    validate_composite_margin "Top" "${COMPOSITE_MARGIN_TOP}"
    validate_composite_margin "Bottom" "${COMPOSITE_MARGIN_BOTTOM}"

    connector="$(composite_connector_name)"
    case "${COMPOSITE_TV_NORM}" in
        PAL|PAL-N|SECAM) mode_spec="720x576@50i" ;;
        *) mode_spec="720x480@60i" ;;
    esac

    cp -n "${cmdline_path}" "${cmdline_path}.emu-sff-backup"
    sed -i -E "s|[[:space:]]+video=${connector}:[^[:space:]]+||g" "${cmdline_path}"
    sed -i "1 s/$/ video=${connector}:${mode_spec},margin_left=${COMPOSITE_MARGIN_LEFT},margin_right=${COMPOSITE_MARGIN_RIGHT},margin_top=${COMPOSITE_MARGIN_TOP},margin_bottom=${COMPOSITE_MARGIN_BOTTOM}/" "${cmdline_path}"

    print_info "Set ${connector} margins to left=${COMPOSITE_MARGIN_LEFT}, right=${COMPOSITE_MARGIN_RIGHT}, top=${COMPOSITE_MARGIN_TOP}, bottom=${COMPOSITE_MARGIN_BOTTOM}."
    print_warn "Reboot to apply the new composite margins."
}

do_composite_margins() {
    local input_value

    if ! load_state_file; then
        print_error "No emu-sff installation state found. Run setup first."
        return 1
    fi
    if [[ "${VIDEO_OUTPUT_MODE}" != "rpi-composite" ]]; then
        print_error "The saved video path is ${VIDEO_OUTPUT_MODE}, not rpi-composite."
        return 1
    fi

    if (( $# == 4 )); then
        COMPOSITE_MARGIN_LEFT="$1"
        COMPOSITE_MARGIN_RIGHT="$2"
        COMPOSITE_MARGIN_TOP="$3"
        COMPOSITE_MARGIN_BOTTOM="$4"
    elif (( $# == 0 )); then
        read -r -p "Left margin [${COMPOSITE_MARGIN_LEFT}]: " input_value
        COMPOSITE_MARGIN_LEFT="${input_value:-${COMPOSITE_MARGIN_LEFT}}"
        read -r -p "Right margin [${COMPOSITE_MARGIN_RIGHT}]: " input_value
        COMPOSITE_MARGIN_RIGHT="${input_value:-${COMPOSITE_MARGIN_RIGHT}}"
        read -r -p "Top margin [${COMPOSITE_MARGIN_TOP}]: " input_value
        COMPOSITE_MARGIN_TOP="${input_value:-${COMPOSITE_MARGIN_TOP}}"
        read -r -p "Bottom margin [${COMPOSITE_MARGIN_BOTTOM}]: " input_value
        COMPOSITE_MARGIN_BOTTOM="${input_value:-${COMPOSITE_MARGIN_BOTTOM}}"
    else
        print_error "Usage: sudo ./emu-sff.sh composite-margins [LEFT RIGHT TOP BOTTOM]"
        return 1
    fi

    apply_composite_margins
    save_state_file
}

remove_tty_profile_hook() {
    local desktop_home profile_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    for profile_path in "${desktop_home}/.profile" "${desktop_home}/.bash_profile" "${desktop_home}/.zprofile"; do
        if [[ -f "${profile_path}" ]]; then
            sed -i '/^# BEGIN emu-sff RetroArch TTY autostart$/,/^# END emu-sff RetroArch TTY autostart$/d' "${profile_path}"
        fi
    done
}

configure_tty_profile_hook() {
    local desktop_home user_config_dir hook_path profile_path login_shell

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    user_config_dir="${desktop_home}/.config/emu-sff"
    hook_path="${user_config_dir}/retroarch-tty-autostart.sh"

    render_template "${EMU_SFF_TEMPLATES_DIR}/retroarch-tty-autostart.sh.tpl" "${hook_path}" \
        "RETROARCH_LAUNCHER_PATH=${user_config_dir}/launch-retroarch-crt.sh"
    chmod 0755 "${hook_path}"

    remove_tty_profile_hook
    profile_path="${desktop_home}/.profile"
    login_shell="$(getent passwd "${DESKTOP_USER}" | cut -d: -f7)"
    case "${login_shell##*/}" in
        bash)
            if [[ -f "${desktop_home}/.bash_profile" ]]; then
                profile_path="${desktop_home}/.bash_profile"
            fi
            ;;
        zsh) profile_path="${desktop_home}/.zprofile" ;;
    esac
    if [[ ! -f "${profile_path}" ]]; then
        touch "${profile_path}"
    fi
    printf '\n# BEGIN emu-sff RetroArch TTY autostart\n. "%s"\n# END emu-sff RetroArch TTY autostart\n' \
        "${hook_path}" >> "${profile_path}"
    chown "${DESKTOP_USER}:${DESKTOP_USER}" "${profile_path}" "${hook_path}"
}

do_tty_autostart() {
    if ! load_state_file; then
        print_error "No emu-sff installation state found. Run setup first."
        return 1
    fi
    if [[ "${VIDEO_OUTPUT_MODE}" != "rpi-composite" ]]; then
        print_error "TTY autostart is only configured for the rpi-composite video path."
        return 1
    fi

    RETROARCH_AUTOSTART="1"
    generate_crt_stack
    save_state_file

    if ! retroarch --features 2>/dev/null | grep -A1 '^KMS:' | grep -qi 'yes'; then
        print_warn "This RetroArch build did not report KMS/EGL support; direct TTY video may not start."
    fi
    print_info "RetroArch TTY autostart is enabled for ${DESKTOP_USER} on /dev/tty1."
    print_info "Log out and back in on tty1 to launch it. Use tty2 or SSH for maintenance."
}

configure_rpi_composite_output() {
    local boot_config cmdline_path

    if [[ -f /boot/firmware/config.txt ]]; then
        boot_config="/boot/firmware/config.txt"
        cmdline_path="/boot/firmware/cmdline.txt"
    elif [[ -f /boot/config.txt ]]; then
        boot_config="/boot/config.txt"
        cmdline_path="/boot/cmdline.txt"
    else
        print_error "Could not find the Raspberry Pi boot config (config.txt)."
        return 1
    fi

    if [[ ! -f "${cmdline_path}" ]]; then
        print_error "Could not find Raspberry Pi kernel command line at ${cmdline_path}."
        return 1
    fi

    cp -n "${boot_config}" "${boot_config}.emu-sff-backup"
    cp -n "${cmdline_path}" "${cmdline_path}.emu-sff-backup"

    # Pi 4 requires TV out to be enabled, and current KMS-based Raspberry Pi OS
    # also requires the composite parameter on the vc4-kms-v3d overlay.
    if grep -Eq '^[[:space:]]*enable_tvout=' "${boot_config}"; then
        sed -i -E 's/^[[:space:]]*enable_tvout=.*/enable_tvout=1/' "${boot_config}"
    else
        printf '\n# Enabled by emu-sff for the 3.5 mm A/V jack\nenable_tvout=1\n' >> "${boot_config}"
    fi

    if ! grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d([^#]*,)?composite([,[:space:]]|$)' "${boot_config}"; then
        if grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d([,[:space:]]|$)' "${boot_config}"; then
            sed -i -E '/^[[:space:]]*dtoverlay=vc4-kms-v3d([,[:space:]]|$)/ s/^([[:space:]]*dtoverlay=vc4-kms-v3d[^#[:space:]]*)([[:space:]]*(#.*)?)$/\1,composite\2/' "${boot_config}"
        else
            printf 'dtoverlay=vc4-kms-v3d,composite\n' >> "${boot_config}"
        fi
    fi

    if grep -Eq '(^|[[:space:]])vc4\.tv_norm=' "${cmdline_path}"; then
        sed -i -E "s/(^|[[:space:]])vc4\.tv_norm=[^[:space:]]+/\\1vc4.tv_norm=${COMPOSITE_TV_NORM}/" "${cmdline_path}"
    else
        sed -i "1 s/$/ vc4.tv_norm=${COMPOSITE_TV_NORM}/" "${cmdline_path}"
    fi

    COMPOSITE_MARGIN_LEFT="${COMPOSITE_MARGIN_LEFT:-${DEFAULT_COMPOSITE_MARGIN_LEFT}}"
    COMPOSITE_MARGIN_RIGHT="${COMPOSITE_MARGIN_RIGHT:-${DEFAULT_COMPOSITE_MARGIN_RIGHT}}"
    COMPOSITE_MARGIN_TOP="${COMPOSITE_MARGIN_TOP:-${DEFAULT_COMPOSITE_MARGIN_TOP}}"
    COMPOSITE_MARGIN_BOTTOM="${COMPOSITE_MARGIN_BOTTOM:-${DEFAULT_COMPOSITE_MARGIN_BOTTOM}}"
    apply_composite_margins

    print_info "Configured Raspberry Pi composite output (${COMPOSITE_TV_NORM}) in ${boot_config}."
    print_warn "HDMI output will be disabled and a reboot is required before composite output is active."
}

generate_crt_stack() {
    local desktop_home user_config_dir user_service_dir autostart_dir launcher_path crt_script_path safety_path arm_path disarm_path retroarch_config_template tty_config_path

    desktop_home="$(desktop_user_home "${DESKTOP_USER}")"
    if [[ -z "${desktop_home}" ]]; then
        print_error "Could not resolve home directory for desktop user ${DESKTOP_USER}."
        exit 1
    fi

    user_config_dir="${desktop_home}/.config/emu-sff"
    user_service_dir="${desktop_home}/.config/systemd/user"
    autostart_dir="${desktop_home}/.config/autostart"
    launcher_path="${user_config_dir}/launch-retroarch-crt.sh"
    crt_script_path="${user_config_dir}/apply-crt-mode.sh"
    safety_path="${user_config_dir}/crt-safety.conf"
    arm_path="${user_config_dir}/arm-crt-output.sh"
    disarm_path="${user_config_dir}/disarm-crt-output.sh"
    tty_config_path="${user_config_dir}/retroarch-composite-tty.cfg"

    ensure_directory "${user_config_dir}"
    ensure_directory "${user_service_dir}"
    ensure_directory "${autostart_dir}"

    if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" ]]; then
        render_template \
            "${EMU_SFF_TEMPLATES_DIR}/crt-mode.sh.tpl" \
            "${crt_script_path}" \
            "CRT_OUTPUT=${CRT_OUTPUT}" \
            "SUPER_MODE_NAME=${SUPER_MODE_NAME}" \
            "SUPER_MODELINE=${SUPER_MODELINE}" \
            "CRT_SAFETY_PATH=${safety_path}"
        chmod 0755 "${crt_script_path}"

        render_template "${EMU_SFF_TEMPLATES_DIR}/crt-safety.conf.tpl" "${safety_path}" \
            "SUPER_MODE_NAME=${SUPER_MODE_NAME}" "SUPER_MODELINE=${SUPER_MODELINE}"
        render_template "${EMU_SFF_TEMPLATES_DIR}/crt-arm-toggle.sh.tpl" "${arm_path}" \
            "CRT_SAFETY_PATH=${safety_path}" "CRT_ARMED_VALUE=1"
        render_template "${EMU_SFF_TEMPLATES_DIR}/crt-arm-toggle.sh.tpl" "${disarm_path}" \
            "CRT_SAFETY_PATH=${safety_path}" "CRT_ARMED_VALUE=0"
        chmod 0755 "${arm_path}" "${disarm_path}"
        retroarch_config_template="${EMU_SFF_TEMPLATES_DIR}/retroarch-crt.cfg.tpl"
    else
        rm -f "${crt_script_path}" "${safety_path}" "${arm_path}" "${disarm_path}"
        retroarch_config_template="${EMU_SFF_TEMPLATES_DIR}/retroarch-composite.cfg.tpl"
        render_template "${EMU_SFF_TEMPLATES_DIR}/retroarch-composite-tty.cfg.tpl" "${tty_config_path}"
    fi

    render_template \
        "${retroarch_config_template}" \
        "${user_config_dir}/retroarch-crt.cfg" \
        "SUPER_WIDTH=${SUPER_WIDTH}" \
        "SUPER_HEIGHT=${SUPER_HEIGHT}"

    render_template \
        "${EMU_SFF_TEMPLATES_DIR}/retroarch-launcher.sh.tpl" \
        "${launcher_path}" \
        "CRT_SCRIPT_PATH=${crt_script_path}" \
        "RETROARCH_CONFIG_PATH=${user_config_dir}/retroarch-crt.cfg" \
        "RETROARCH_TTY_CONFIG_PATH=${tty_config_path}" \
        "CRT_SAFETY_PATH=${safety_path}" \
        "VIDEO_OUTPUT_MODE=${VIDEO_OUTPUT_MODE}"
    chmod 0755 "${launcher_path}"

    if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" ]]; then
        render_template "${EMU_SFF_TEMPLATES_DIR}/retroarch-crt-setup.service.tpl" \
            "${user_service_dir}/emu-sff-crt-mode.service" "CRT_SCRIPT_PATH=${crt_script_path}"
    else
        rm -f "${user_service_dir}/emu-sff-crt-mode.service"
    fi

    if [[ "${RETROARCH_AUTOSTART}" == "1" ]]; then
        render_template "${EMU_SFF_TEMPLATES_DIR}/retroarch-autostart.desktop.tpl" \
            "${autostart_dir}/emu-sff-retroarch.desktop" "RETROARCH_LAUNCHER_PATH=${launcher_path}"
        if [[ "${VIDEO_OUTPUT_MODE}" == "rpi-composite" ]]; then
            configure_tty_profile_hook
        fi
    else
        rm -f "${autostart_dir}/emu-sff-retroarch.desktop"
        remove_tty_profile_hook
        rm -f "${user_config_dir}/retroarch-tty-autostart.sh"
    fi

    chown -R "${DESKTOP_USER}:${DESKTOP_USER}" "${user_config_dir}" "${user_service_dir}" "${autostart_dir}"

    if command -v runuser >/dev/null 2>&1; then
        if ! runuser -u "${DESKTOP_USER}" -- systemctl --user daemon-reload >/dev/null 2>&1; then
            print_warn "Skipped systemctl --user daemon-reload because ${DESKTOP_USER} does not have an active user bus yet."
            print_warn "This is normal on headless setup or before the desktop user logs in."
        fi
    fi

    if [[ "${VIDEO_OUTPUT_MODE}" == "xrandr" ]]; then
        print_warn "CRT mode auto-apply is not enabled by setup."
        print_warn "Arm the CRT path manually with ${arm_path} only after verifying the chain on a safe display."
        print_warn "The launcher and mode script will refuse to run while CRT_ARMED=0 in ${safety_path}."
    elif [[ "${RETROARCH_AUTOSTART}" == "1" ]]; then
        print_info "RetroArch will start automatically when ${DESKTOP_USER} logs into the desktop."
    fi
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
        if prompt_step "[CRT] Configure video output + RetroArch" "Configure the selected ${VIDEO_OUTPUT_MODE} video path, RetroArch profile, launcher, and optional desktop autostart."; then
            if [[ "${VIDEO_OUTPUT_MODE}" == "rpi-composite" ]]; then
                configure_rpi_composite_output
            fi
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
