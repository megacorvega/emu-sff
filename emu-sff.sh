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
    local columns inner_width left_width right_width title

    columns="$(terminal_columns)"
    if (( columns < 84 )); then
        columns=84
    elif (( columns > 120 )); then
        columns=120
    fi

    inner_width=$((columns - 4))
    left_width=$(((inner_width - 3) / 2))
    right_width=$((inner_width - left_width - 3))
    title=" emu-sff utility "

    printf "\033[2J\033[H"
    printf "${COLOR_MUTED}%s${COLOR_RESET}\n" "$(repeat_char "=" "${columns}")"
    printf "${COLOR_PANEL}--%s%s%s--${COLOR_RESET}\n" \
        "${title}" \
        "$(repeat_char "-" $((columns - ${#title} - 4)))" \
        ""
    printf "${COLOR_PANEL}.%s.${COLOR_RESET}\n" "$(repeat_char "-" "${inner_width}")"
    print_panel_line "${left_width}" "${right_width}" "Welcome back to emu-sff" "Current commands"
    print_panel_line "${left_width}" "${right_width}" "" "1. setup / install"
    print_logo_panel_line "${left_width}" "${right_width}" "          ████████" "2. status"
    print_logo_panel_line "${left_width}" "${right_width}" "          ██      " "3. uninstall"
    print_logo_panel_line "${left_width}" "${right_width}" "          ██████  " "4. exit"
    print_logo_panel_line "${left_width}" "${right_width}" "          ██      " ""
    print_logo_panel_line "${left_width}" "${right_width}" "          ████████" ""
    print_panel_line "${left_width}" "${right_width}" "" ""
    print_panel_line "${left_width}" "${right_width}" "Bitmap epsilon mark" ""
    print_panel_line "${left_width}" "${right_width}" "Main entrypoint for ROM share," "Notes"
    print_panel_line "${left_width}" "${right_width}" "SMB intake, and CRT launch files." "Lightweight ANSI dashboard"
    print_panel_line "${left_width}" "${right_width}" "" "No extra packages required"
    print_panel_line "${left_width}" "${right_width}" "Project root" ""
    print_panel_line "${left_width}" "${right_width}" "${SCRIPT_DIR}" ""
    printf "${COLOR_PANEL}'%s'${COLOR_RESET}\n" "$(repeat_char "-" "${inner_width}")"
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
