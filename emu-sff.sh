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

show_menu() {
    local columns inner_width left_width right_width
    local cpu_usage ram_usage storage_usage network_speed
    local summary_line_1 summary_line_2 summary_line_3 summary_line_4
    local -a summary_lines
    local summary_index

    columns="$(terminal_columns)"
    if (( columns < 84 )); then
        columns=84
    elif (( columns > 104 )); then
        columns=104
    fi

    inner_width=$((columns - 4))
    left_width=$(((inner_width - 3) * 3 / 5))
    right_width=$((inner_width - left_width - 3))
    cpu_usage="$(menu_cpu_usage)"
    ram_usage="$(menu_ram_usage)"
    storage_usage="$(menu_storage_usage)"
    network_speed="$(menu_network_speed)"
    summary_lines=()
    summary_index=0
    while IFS= read -r line; do
        summary_lines[summary_index]="${line}"
        summary_index=$((summary_index + 1))
    done < <(menu_system_summary_lines)
    summary_line_1="${summary_lines[0]:-Docker: unknown}"
    summary_line_2="${summary_lines[1]:-Config state: unknown}"
    summary_line_3="${summary_lines[2]:-LAN IP: unknown}"
    summary_line_4="${summary_lines[3]:-CRT config: unknown}"

    printf "\033[2J\033[H"
    printf "${COLOR_PANEL}.%s.${COLOR_RESET}\n" "$(repeat_char "-" $((inner_width + 2)))"
    print_panel_line "${left_width}" "${right_width}" "emu-sff utility" "Current commands"
    print_panel_line "${left_width}" "${right_width}" "                            " "1. setup / install"
    print_logo_panel_line "${left_width}" "${right_width}" "            ██████     " "2. status"
    print_logo_panel_line "${left_width}" "${right_width}" "           ███   ██    " "3. uninstall"
    print_logo_panel_line "${left_width}" "${right_width}" "             ███       " "4. exit"
    print_logo_panel_line "${left_width}" "${right_width}" "           ███   ██    " ""
    print_logo_panel_line "${left_width}" "${right_width}" "            ██████     " ""
    print_panel_line "${left_width}" "${right_width}" "" ""
    print_panel_line "${left_width}" "${right_width}" "Bitmap epsilon mark" "System summary"
    print_panel_line "${left_width}" "${right_width}" "CPU: ${cpu_usage:-n/a}" "${summary_line_1}"
    print_panel_line "${left_width}" "${right_width}" "RAM: ${ram_usage:-n/a}" "${summary_line_2}"
    print_panel_line "${left_width}" "${right_width}" "Disk: ${storage_usage:-n/a}" "${summary_line_3}"
    print_panel_line "${left_width}" "${right_width}" "Net: ${network_speed:-n/a}" "${summary_line_4}"
    print_panel_line "${left_width}" "${right_width}" "Project root" ""
    print_panel_line "${left_width}" "${right_width}" "${SCRIPT_DIR}" ""
    printf "${COLOR_PANEL}'%s'${COLOR_RESET}\n" "$(repeat_char "-" $((inner_width + 2)))"
    printf "\n${COLOR_MUTED}> Select an option [1-4]: ${COLOR_RESET}"

    read -r option
    case "${option}" in
        1) do_setup ;;
        2) do_status ;;
        3) do_uninstall ;;
        4) exit 0 ;;
        *) echo "Invalid option."; show_menu ;;
    esac
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
        "")
            show_menu
            ;;
        *)
            echo "Unknown command: ${1}"
            echo "Usage: sudo ./emu-sff.sh [setup|status|uninstall]"
            exit 1
            ;;
    esac
}

main "${1:-}"
