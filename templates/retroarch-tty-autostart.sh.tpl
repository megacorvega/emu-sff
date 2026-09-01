#!/bin/sh

# Only take over the first local text console. SSH, serial sessions, desktop
# terminals, and the other virtual consoles remain available for maintenance.
if [ "$(tty 2>/dev/null)" = "/dev/tty1" ] && \
   [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && \
   [ "${EMU_SFF_NO_AUTOSTART:-0}" != "1" ]; then
    EMU_SFF_TTY=1
    export EMU_SFF_TTY
    "__RETROARCH_LAUNCHER_PATH__"
    retroarch_status=$?
    echo "RetroArch exited with status ${retroarch_status}. The tty1 shell will remain available." >&2
    echo "To retry manually: EMU_SFF_TTY=1 __RETROARCH_LAUNCHER_PATH__" >&2
fi
