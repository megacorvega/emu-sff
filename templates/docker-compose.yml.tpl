services:
  samba:
    image: dperson/samba
    container_name: emu-samba
    network_mode: host
    volumes:
      - __STORAGE_PATH__:__STORAGE_PATH__
      - __CONFIG_PATH__/samba/smb.conf:/etc/samba/smb.conf:ro
    restart: unless-stopped

  dnsmasq:
    image: dockurr/dnsmasq:2.93
    container_name: emu-dhcp
    network_mode: host
    cap_add:
      - NET_RAW
      - NET_ADMIN
    volumes:
      - __CONFIG_PATH__/dnsmasq/dnsmasq.conf:/etc/dnsmasq.conf:ro
    restart: unless-stopped
