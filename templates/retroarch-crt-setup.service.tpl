[Unit]
Description=Apply emu-sff CRT mode at graphical login
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=__CRT_SCRIPT_PATH__

[Install]
WantedBy=default.target
