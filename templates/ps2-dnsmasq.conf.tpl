# DHCP only: the PS2 does not need DNS on this isolated Ethernet link.
port=0
interface=__LAN_IF__
bind-dynamic
dhcp-range=192.168.2.2,192.168.2.100,12h
