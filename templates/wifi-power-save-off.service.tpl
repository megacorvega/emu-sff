[Unit]
Description=Disable Wi-Fi power saving for emu-sff
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/iw dev __WLAN_IF__ set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
