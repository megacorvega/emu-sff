#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/setup.sh
source "${SCRIPT_DIR}/lib/setup.sh"
# shellcheck source=lib/status.sh
source "${SCRIPT_DIR}/lib/status.sh"
# shellcheck source=lib/uninstall.sh
source "${SCRIPT_DIR}/lib/uninstall.sh"

MENU_CPU_USAGE=""
MENU_RAM_USAGE=""
MENU_STORAGE_USAGE=""
MENU_NETWORK_SPEED=""
MENU_SUMMARY_LINE_1=""
MENU_SUMMARY_LINE_2=""
MENU_SUMMARY_LINE_3=""
MENU_SUMMARY_LINE_4=""

refresh_menu_snapshot() {
    local -a summary_lines
    local summary_index

    MENU_CPU_USAGE="$(menu_cpu_usage)"
    MENU_RAM_USAGE="$(menu_ram_usage)"
    MENU_STORAGE_USAGE="$(menu_storage_usage)"
    MENU_NETWORK_SPEED="$(menu_network_speed)"

    summary_lines=()
    summary_index=0
    while IFS= read -r line; do
        summary_lines[summary_index]="${line}"
        summary_index=$((summary_index + 1))
    done < <(menu_system_summary_lines)

    MENU_SUMMARY_LINE_1="${summary_lines[0]:-Docker: unknown}"
    MENU_SUMMARY_LINE_2="${summary_lines[1]:-Config state: unknown}"
    MENU_SUMMARY_LINE_3="${summary_lines[2]:-LAN IP: unknown}"
    MENU_SUMMARY_LINE_4="${summary_lines[3]:-CRT config: unknown}"
}

show_menu() {
    calculate_ui_layout

    if (( UI_COMPACT_MODE == 1 )); then
        render_compact_box
        pause_for_keypress "Terminal too small for full UI"
        return 1
    fi

    printf "\033[2J\033[H"
    print_ui_margin
    printf "${COLOR_PANEL}${BOX_TOP_LEFT}%s${BOX_TOP_RIGHT}${COLOR_RESET}\n" "$(repeat_char "${BOX_HORIZONTAL}" $((UI_INNER_WIDTH + 2)))"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "emu-sff utility" "Current commands"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "" "1. setup / install"
    print_ui_margin; print_logo_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "            ██████     " "2. status"
    print_ui_margin; print_logo_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "           ███   ██    " "3. uninstall"
    print_ui_margin; print_logo_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "             ███       " "4. refresh"
    print_ui_margin; print_logo_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "           ███   ██    " "5. exit"
    print_ui_margin; print_logo_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "            ██████     " ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Bitmap epsilon mark" "System summary"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "CPU: ${MENU_CPU_USAGE:-n/a}" "${MENU_SUMMARY_LINE_1}"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "RAM: ${MENU_RAM_USAGE:-n/a}" "${MENU_SUMMARY_LINE_2}"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Disk: ${MENU_STORAGE_USAGE:-n/a}" "${MENU_SUMMARY_LINE_3}"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Net: ${MENU_NETWORK_SPEED:-n/a}" "${MENU_SUMMARY_LINE_4}"
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "Project root" ""
    print_ui_margin; print_panel_line "${UI_LEFT_WIDTH}" "${UI_RIGHT_WIDTH}" "${SCRIPT_DIR}" ""
    print_ui_margin
    printf "${COLOR_PANEL}${BOX_BOTTOM_LEFT}%s${BOX_BOTTOM_RIGHT}${COLOR_RESET}\n" "$(repeat_char "${BOX_HORIZONTAL}" $((UI_INNER_WIDTH + 2)))"
    printf "\n"
    print_ui_margin
    printf "${COLOR_MUTED}> Select an option [1-5]: ${COLOR_RESET}"

    read -r option
    case "${option}" in
        1) do_setup ;;
        2) do_status ;;
        3) do_uninstall ;;
        4) do_refresh ;;
        5) return 1 ;;
        *) ;;
    esac

    return 0
}

run_interactive_utility() {
    enter_alt_screen
    trap leave_alt_screen EXIT

    while true; do
        refresh_menu_snapshot
        if ! show_menu; then
            break
        fi
    done
}

main() {
    require_root

    case "${1:-}" in
        setup|install)
            do_setup
            ;;
        status)
            do_status
            ;;
        uninstall)
            do_uninstall
            ;;
        refresh)
            do_refresh
            ;;
        "")
            run_interactive_utility
            ;;
        *)
            echo "Unknown command: ${1}"
            echo "Usage: sudo ./emu-sff.sh [setup|status|uninstall|refresh]"
            exit 1
            ;;
    esac
}

main "${1:-}"
