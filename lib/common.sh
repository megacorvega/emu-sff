#!/usr/bin/env bash

set -euo pipefail

EMU_SFF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMU_SFF_TEMPLATES_DIR="${EMU_SFF_ROOT}/templates"
EMU_SFF_STATE_DIR="/etc/emu-sff"
EMU_SFF_STATE_FILE="${EMU_SFF_STATE_DIR}/emu-sff.env"
EMU_SFF_INSTALL_DIR="/usr/local/lib/emu-sff"
EMU_SFF_LAUNCHER_PATH="/usr/local/bin/emu-sff"

DEFAULT_CONFIG_PATH="/opt/emu-sff"
DEFAULT_STORAGE_PATH="/srv/emu-sff/storage"
DEFAULT_DESKTOP_OUTPUT="DP-1"
DEFAULT_SUPER_WIDTH="2560"
DEFAULT_SUPER_HEIGHT="240"
DEFAULT_SUPER_MODE_NAME="2560x240_60.00"
DEFAULT_SUPER_MODELINE="50.00 2560 2720 2960 3200 240 244 246 261 -hsync -vsync"

COLOR_RESET=$'\033[0m'
COLOR_PANEL=$'\033[38;5;172m'
COLOR_MUTED=$'\033[38;5;244m'
COLOR_TEXT=$'\033[38;5;188m'
COLOR_LOGO=$'\033[38;5;172m'
COLOR_TITLE=$'\033[38;5;172m'
COLOR_OK=$'\033[38;5;114m'
COLOR_WARN=$'\033[38;5;221m'
COLOR_ERROR=$'\033[38;5;203m'
EMU_SFF_UI_ACTIVE="${EMU_SFF_UI_ACTIVE:-0}"

BOX_TOP_LEFT="┌"
BOX_TOP_RIGHT="┐"
BOX_BOTTOM_LEFT="└"
BOX_BOTTOM_RIGHT="┘"
BOX_HORIZONTAL="─"
BOX_VERTICAL="│"
BOX_TEE_DOWN="┬"
BOX_TEE_UP="┴"
BOX_TEE_RIGHT="├"
BOX_TEE_LEFT="┤"
BOX_CROSS="┼"
UI_TOTAL_WIDTH=0
UI_INNER_WIDTH=0
UI_LEFT_WIDTH=0
UI_RIGHT_WIDTH=0
UI_LEFT_MARGIN=0
UI_COMPACT_MODE=0

print_info() {
    printf '[INFO] %s\n' "$1"
}

print_warn() {
    printf '[WARN] %s\n' "$1"
}

print_error() {
    printf '[ERROR] %s\n' "$1" >&2
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        print_error "Please run this script as root or with sudo."
        exit 1
    fi
}

prompt_step() {
    local step_title="$1"
    local step_desc="$2"

    echo
    echo "${step_title}"
    echo "Description: ${step_desc}"

    while true; do
        read -r -p "Do you want to proceed with this step? [Y/n]: " consent
        consent="${consent:-Y}"

        case "${consent}" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

print_status() {
    local label="$1"
    local status="$2"

    case "${status}" in
        OK)
            printf '%s \e[32m[OK]\e[0m\n' "${label}"
            ;;
        WARN)
            printf '%s \e[33m[WARN]\e[0m\n' "${label}"
            ;;
        *)
            printf '%s \e[31m[ERROR]\e[0m\n' "${label}"
            ;;
    esac
}

detect_first_interface() {
    local pattern="$1"
    ls /sys/class/net 2>/dev/null | grep -E "${pattern}" | head -n 1 || true
}

ensure_directory() {
    local dir_path="$1"
    local mode="${2:-0755}"

    mkdir -p "${dir_path}"
    chmod "${mode}" "${dir_path}"
}

quote_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_template() {
    local template_path="$1"
    local destination_path="$2"
    shift 2

    local sed_args=()
    local pair key value

    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        sed_args+=("-e" "s|__${key}__|$(quote_sed_replacement "${value}")|g")
    done

    sed "${sed_args[@]}" "${template_path}" > "${destination_path}"
}

save_state_file() {
    ensure_directory "${EMU_SFF_STATE_DIR}"

    {
        printf 'SETUP_PROFILE=%q\n' "${SETUP_PROFILE:-full}"
        printf 'SERVICE_BACKEND=%q\n' "${SERVICE_BACKEND:-docker}"
        printf 'OPL_ENABLED=%q\n' "${OPL_ENABLED:-0}"
        printf 'LAN_IF=%q\n' "${LAN_IF}"
        printf 'WLAN_IF=%q\n' "${WLAN_IF}"
        printf 'STORAGE_PATH=%q\n' "${STORAGE_PATH}"
        printf 'CONFIG_PATH=%q\n' "${CONFIG_PATH}"
        printf 'DESKTOP_USER=%q\n' "${DESKTOP_USER}"
        printf 'CRT_OUTPUT=%q\n' "${CRT_OUTPUT}"
        printf 'SUPER_WIDTH=%q\n' "${SUPER_WIDTH}"
        printf 'SUPER_HEIGHT=%q\n' "${SUPER_HEIGHT}"
        printf 'SUPER_MODE_NAME=%q\n' "${SUPER_MODE_NAME}"
        printf 'SUPER_MODELINE=%q\n' "${SUPER_MODELINE}"
    } > "${EMU_SFF_STATE_FILE}"
}

normalize_install_state() {
    local legacy_mode="${SETUP_MODE:-}"

    SETUP_PROFILE="${SETUP_PROFILE:-${legacy_mode:-full}}"
    if [[ -z "${SERVICE_BACKEND:-}" ]]; then
        if [[ "${legacy_mode}" == "ps2" ]]; then
            SERVICE_BACKEND="native"
        else
            SERVICE_BACKEND="docker"
        fi
    fi
    if [[ -z "${OPL_ENABLED:-}" ]]; then
        if [[ "${legacy_mode}" == "ps2" ]]; then
            OPL_ENABLED="1"
        else
            OPL_ENABLED="0"
        fi
    fi
}

load_state_file() {
    if [[ -f "${EMU_SFF_STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${EMU_SFF_STATE_FILE}"
        normalize_install_state
        return 0
    fi

    return 1
}

desktop_user_home() {
    local desktop_user="$1"
    getent passwd "${desktop_user}" | cut -d: -f6
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        print_error "Missing command: ${command_name}"
        return 1
    fi
}

write_file_if_missing_notice() {
    local path="$1"
    print_info "Generated ${path}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

terminal_columns() {
    if command -v tput >/dev/null 2>&1; then
        tput cols 2>/dev/null || echo 100
    else
        echo 100
    fi
}

calculate_ui_layout() {
    local term_columns desired_width minimum_width

    term_columns="$(terminal_columns)"
    desired_width=76
    minimum_width=74

    UI_COMPACT_MODE=0
    if (( term_columns < minimum_width )); then
        UI_COMPACT_MODE=1
        UI_TOTAL_WIDTH=11
        UI_INNER_WIDTH=9
        UI_LEFT_WIDTH=0
        UI_RIGHT_WIDTH=0
        UI_LEFT_MARGIN=0
        return 0
    fi

    UI_TOTAL_WIDTH="${desired_width}"
    if (( term_columns < desired_width )); then
        UI_TOTAL_WIDTH="${term_columns}"
    fi

    UI_LEFT_MARGIN=0
    UI_INNER_WIDTH=$((UI_TOTAL_WIDTH - 4))
    UI_LEFT_WIDTH=$(((UI_INNER_WIDTH - 3) * 11 / 20))
    UI_RIGHT_WIDTH=$((UI_INNER_WIDTH - UI_LEFT_WIDTH - 3))
}

print_ui_margin() {
    if (( UI_LEFT_MARGIN > 0 )); then
        printf '%*s' "${UI_LEFT_MARGIN}" ""
    fi
}

render_compact_box() {
    printf "\033[2J\033[H"
    print_ui_margin
    printf "${COLOR_PANEL}${BOX_TOP_LEFT}${BOX_HORIZONTAL} emu-sff ${BOX_HORIZONTAL}${BOX_TOP_RIGHT}${COLOR_RESET}\n"
}

enter_alt_screen() {
    if [[ "${EMU_SFF_UI_ACTIVE}" == "1" ]]; then
        return 0
    fi

    if command_exists tput; then
        tput smcup 2>/dev/null || printf '\033[?1049h'
        tput civis 2>/dev/null || true
    else
        printf '\033[?1049h'
    fi

    EMU_SFF_UI_ACTIVE=1
}

leave_alt_screen() {
    if [[ "${EMU_SFF_UI_ACTIVE}" != "1" ]]; then
        return 0
    fi

    if command_exists tput; then
        tput cnorm 2>/dev/null || true
        tput rmcup 2>/dev/null || printf '\033[?1049l'
    else
        printf '\033[?1049l'
    fi

    EMU_SFF_UI_ACTIVE=0
}

pause_for_keypress() {
    local prompt_text="${1:-Press any key to return}"

    if [[ -t 0 ]]; then
        printf "\n${COLOR_MUTED}> %s${COLOR_RESET}" "${prompt_text}"
        IFS= read -r -s -n 1 _
        printf "\n"
    fi
}

repeat_char() {
    local char="$1"
    local count="$2"
    local out=""

    while (( count > 0 )); do
        out="${out}${char}"
        count=$((count - 1))
    done

    printf '%s' "${out}"
}

pad_text() {
    local width="$1"
    local text="$2"
    local text_length plain_text

    plain_text="$(printf '%b' "${text}" | sed -E $'s/\x1B\\[[0-9;]*[A-Za-z]//g')"
    text_length=${#plain_text}

    if (( text_length > width )); then
        printf '%s' "${plain_text:0:width}"
        return
    fi

    printf '%b' "${text}"
    repeat_char " " $((width - text_length))
}

print_panel_line() {
    local left_width="$1"
    local right_width="$2"
    local left_text="${3:-}"
    local right_text="${4:-}"

    printf "${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET} ${COLOR_TEXT}%s${COLOR_RESET} ${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET} ${COLOR_TEXT}%s${COLOR_RESET} ${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET}\n" \
        "$(pad_text "${left_width}" "${left_text}")" \
        "$(pad_text "${right_width}" "${right_text}")"
}

print_panel_divider() {
    local left_width="$1"
    local right_width="$2"

    printf "${COLOR_PANEL}${BOX_TEE_RIGHT}%s${BOX_CROSS}%s${BOX_TEE_LEFT}${COLOR_RESET}\n" \
        "$(repeat_char "${BOX_HORIZONTAL}" $((left_width + 2)))" \
        "$(repeat_char "${BOX_HORIZONTAL}" $((right_width + 2)))"
}

print_logo_panel_line() {
    local left_width="$1"
    local right_width="$2"
    local logo_text="${3:-}"
    local right_text="${4:-}"

    printf "${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET} ${COLOR_LOGO}%s${COLOR_RESET} ${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET} ${COLOR_TEXT}%s${COLOR_RESET} ${COLOR_PANEL}${BOX_VERTICAL}${COLOR_RESET}\n" \
        "$(pad_text "${left_width}" "${logo_text}")" \
        "$(pad_text "${right_width}" "${right_text}")"
}

status_color() {
    case "$1" in
        OK) printf '%s' "${COLOR_OK}" ;;
        WARN) printf '%s' "${COLOR_WARN}" ;;
        *) printf '%s' "${COLOR_ERROR}" ;;
    esac
}

menu_cpu_usage() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command_exists top; then
            top -l 1 2>/dev/null | awk -F'[:,%]+' '/CPU usage/ { printf "%.1f%% used", 100 - $(NF-1); exit }'
        fi
        if command_exists uptime; then
            uptime 2>/dev/null | awk -F'load averages?: ' 'NF > 1 { split($2, parts, " "); printf "load %s", parts[1]; exit }'
        fi
    elif command_exists top; then
        top -bn1 2>/dev/null | awk -F'[, ]+' '/^%?Cpu\(s\)/ { for (i = 1; i <= NF; i++) if ($i == "id,") { printf "%.1f%% used", 100 - $(i-1); exit } }'
    fi
}

menu_ram_usage() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        vm_stat 2>/dev/null | awk '
            BEGIN { page_size = 16384 }
            /Pages free/ { free = $3 }
            /Pages active/ { active = $3 }
            /Pages inactive/ { inactive = $3 }
            /Pages wired down/ { wired = $4 }
            END {
                gsub(/\./, "", free)
                gsub(/\./, "", active)
                gsub(/\./, "", inactive)
                gsub(/\./, "", wired)
                used = (active + inactive + wired) * page_size / 1024 / 1024 / 1024
                avail = free * page_size / 1024 / 1024 / 1024
                printf "%.1f GiB used, %.1f GiB free", used, avail
            }
        '
    elif command_exists free; then
        free -h 2>/dev/null | awk '/^Mem:/ { printf "%s / %s", $3, $2; exit }'
    fi
}

menu_storage_usage() {
    df -h "${EMU_SFF_ROOT}" 2>/dev/null | awk 'NR==2 { printf "%s used of %s", $3, $2; exit }'
}

menu_default_interface() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
    elif command_exists ip; then
        ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
    fi
}

menu_network_speed() {
    local iface media

    iface="$(menu_default_interface)"
    if [[ -z "${iface}" ]]; then
        printf 'n/a'
        return
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
        media="$(ifconfig "${iface}" 2>/dev/null | awk -F': ' '/media:/{print $2; exit}')"
        if [[ -n "${media}" ]]; then
            printf '%s %s' "${iface}" "${media}"
        else
            printf '%s active' "${iface}"
        fi
    elif [[ -r "/sys/class/net/${iface}/speed" ]]; then
        printf '%s %s Mb/s' "${iface}" "$(cat "/sys/class/net/${iface}/speed" 2>/dev/null)"
    else
        printf '%s active' "${iface}"
    fi
}

menu_system_summary_lines() {
    local service_state state_state lan_state crt_state

    load_state_file >/dev/null 2>&1 || true
    if [[ "${SERVICE_BACKEND:-docker}" == "native" ]]; then
        service_state="Services: native inactive"
        if command_exists systemctl && \
           systemctl is-active --quiet smbd.service 2>/dev/null && \
           systemctl is-active --quiet dnsmasq.service 2>/dev/null; then
            service_state="Services: native active"
        fi
    else
        service_state="Docker: unavailable"
        if command_exists systemctl && systemctl is-active --quiet docker 2>/dev/null; then
            service_state="Docker: active"
        elif command_exists docker; then
            service_state="Docker: installed"
        else
            service_state="Docker: unavailable"
        fi
    fi

    if [[ -f "${EMU_SFF_STATE_FILE}" ]]; then
        state_state="Config state: present"
    else
        state_state="Config state: missing"
    fi

    if command_exists ip && ip addr show 2>/dev/null | grep -q '192.168.2.1/24'; then
        lan_state="LAN IP: 192.168.2.1 set"
    else
        lan_state="LAN IP: not set"
    fi

    if [[ -n "${DESKTOP_USER:-}" ]]; then
        local desktop_home
        desktop_home="$(desktop_user_home "${DESKTOP_USER}" 2>/dev/null || true)"
        if [[ -n "${desktop_home}" && -f "${desktop_home}/.config/emu-sff/retroarch-crt.cfg" ]]; then
            crt_state="CRT config: generated"
        else
            crt_state="CRT config: missing"
        fi
    else
        crt_state="CRT config: unknown"
    fi

    printf '%s\n%s\n%s\n%s\n' "${service_state}" "${state_state}" "${lan_state}" "${crt_state}"
}
