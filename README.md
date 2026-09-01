<div align="center">

  <img src="./assets/emu-sff-icon.svg" alt="emu-sff logo" width="150">

</div>

# emu-sff

`emu-sff` configures a Debian or Ubuntu machine as a retro game server and, optionally, a CRT-oriented RetroArch emulation rig. 

It can:

1. Serve games over an isolated Ethernet connection using DHCP and an SMB guest share.
2. Create the `DVD/` and `CD/` layout expected by PS2 Open PS2 Loader (OPL).
3. Generate RetroArch helpers for either a 15 kHz `xrandr` output or the Raspberry Pi hardware composite jack.
4. Optionally start RetroArch automatically at desktop login.

> [!NOTE]
> Setup choices and paths are saved in `/etc/emu-sff/emu-sff.env`. The `status`, repeated `setup`, and `uninstall` commands use this file to identify the active profile and service backend.

## Quick start

Run the unified setup wizard as root:

```bash
chmod +x emu-sff.sh
sudo ./emu-sff.sh setup
```

The same wizard is available from the interactive menu:

```bash
sudo ./emu-sff.sh
```

## Installation choices

Setup separates the machine's role from the way Samba and dnsmasq are installed.

### Profiles

| Profile | File server | PS2/OPL layout | Wi-Fi tuning | RetroArch and CRT helpers |
| --- | --- | --- | --- | --- |
| `full` | Yes | Optional | Yes | Yes, including optional autostart |
| `ps2` | Yes | Always enabled | No | No |

Use `full` for a desktop emulation workstation. Use `ps2` for a small headless server, such as an Ubuntu Server Raspberry Pi connected directly to a PS2.

### Service backends

| Backend | Samba and dnsmasq run as | Best suited for |
| --- | --- | --- |
| `native` | System services managed by systemd | Minimal or headless installations |
| `docker` | Host-networked containers | Isolating generated service configuration |

Both backends expose the selected storage directory as an SMB guest share named `share`. The Docker dnsmasq image supports AMD64, ARM64, and ARMv7.

When OPL support is enabled, setup:

- creates `<storage-path>/DVD` and `<storage-path>/CD`;
- assigns the selected Ethernet interface `192.168.2.1/24`;
- provides DHCP addresses from `192.168.2.2` through `192.168.2.100`;
- disables DNS on the isolated PS2 link;
- configures an SMB1/NT1 guest share named `share`.

In OPL, use server `192.168.2.1` and share name `share`.

> [!WARNING]
> SMB1/NT1 and guest access are intentionally enabled for legacy clients. Connect the selected Ethernet interface only to the PS2 or another trusted isolated network; do not expose it to the internet or an untrusted LAN.

## Upgrading or changing an installation

You can rerun `sudo ./emu-sff.sh setup` to change profiles or service backends. Existing values become the prompt defaults.

> [!IMPORTANT]
> A legacy PS2 installation is automatically interpreted as `ps2 + native + OPL`. Selecting `full` keeps its storage path and native backend by default, then adds the workstation features. This prevents a second Samba share from being created.

If you deliberately switch between `native` and `docker`, setup removes the emu-sff-managed old backend before starting the new one. This prevents two Samba or dnsmasq instances from competing for the same network ports.

Changing the storage path updates the share configuration but does not move existing game files. Move the files yourself or keep the existing path when prompted.

## Setup steps

Depending on the selected profile and backend, the wizard can:

1. Install the required native packages or Docker Engine.
2. Assign `192.168.2.1/24` to the selected Ethernet interface using Netplan.
3. Disable Wi-Fi power saving for the full profile.
4. Generate and start Samba and dnsmasq using the selected backend.
5. Configure the selected CRT path and generate RetroArch helpers for the full profile.
6. Install the optional global `emu-sff` launcher.

The wizard prompts before performing each step.

## CRT workflows

Setup offers `xrandr` and `rpi-composite` video paths. The generated RetroArch launcher matches the selected path, and setup can install an XDG autostart entry that launches RetroArch when the selected desktop user logs in.

### Raspberry Pi 4 composite output

Choose `rpi-composite` to use the Pi 4's 3.5 mm A/V jack with a TRRS-to-RCA cable. Setup:

- enables TV output and the KMS composite overlay in `config.txt`;
- sets `vc4.tv_norm` in `cmdline.txt` (NTSC by default, with PAL and other supported norms selectable);
- generates a 4:3 RetroArch profile without `xrandr` or dynamic CRT resolution switching;
- optionally creates `~/.config/autostart/emu-sff-retroarch.desktop`.

The installer keeps one-time `.emu-sff-backup` copies of the boot files before changing them. Uninstall leaves the active boot settings and those backups in place to avoid overwriting later boot-file edits; restore the backups manually if you want to revert composite output. Enabling composite disables HDMI output and requires a reboot. RetroArch autostart occurs at graphical desktop login, so configure desktop autologin separately if you want a power-on appliance experience.

The Pi 4 A/V jack uses a TRRS pinout; a physically fitting camcorder cable is not necessarily wired correctly for Raspberry Pi.

### xrandr super-resolution

The CRT workflow assumes:

- Debian or Ubuntu running X11;
- a GPU and driver that accept custom `xrandr` modelines;
- a converter and CRT that can safely accept a 15 kHz signal.

The default target is `2560x240_60.00` with this modeline:

```text
50.00 2560 2720 2960 3200 240 244 246 261 -hsync -vsync
```

Setup generates these files for the selected desktop user:

- `~/.config/emu-sff/apply-crt-mode.sh`
- `~/.config/emu-sff/crt-safety.conf`
- `~/.config/emu-sff/arm-crt-output.sh`
- `~/.config/emu-sff/disarm-crt-output.sh`
- `~/.config/emu-sff/retroarch-crt.cfg`
- `~/.config/emu-sff/launch-retroarch-crt.sh`
- `~/.config/systemd/user/emu-sff-crt-mode.service`
- `~/.config/autostart/emu-sff-retroarch.desktop` (when autostart is selected)

### CRT safety gate

CRT output is disarmed by default. Setup generates the user service but does not enable it. The launcher and mode script refuse to change the display unless:

- `CRT_ARMED=1` is present in `crt-safety.conf`; and
- the configured modeline computes to a plausible 15 kHz horizontal and vertical sync range.

> [!CAUTION]
> The safety gate cannot control firmware, bootloader, display-manager, or pre-login video modes. For first bring-up, keep the CRT disconnected or behind a known-safe switch until the Linux session and modeline have been verified on safe equipment.

The default modeline is only a starting point. Adjust its porch and sync timings if required by your GPU, converter, or display.

## Commands

| Command | Purpose |
| --- | --- |
| `sudo ./emu-sff.sh` | Open the interactive utility |
| `sudo ./emu-sff.sh setup` | Run or update the unified setup |
| `sudo ./emu-sff.sh ps2` | Open setup with the PS2 profile preselected |
| `sudo ./emu-sff.sh status` | Check the saved profile, backend, network, and optional workstation components |
| `sudo ./emu-sff.sh uninstall` | Remove generated configuration and managed services |
| `sudo ./emu-sff.sh refresh` | Refresh the installed global launcher from the current checkout |
| `sudo ./emu-sff.sh composite-margins [L R T B]` | Adjust Raspberry Pi composite overscan margins |

For example, `sudo ./emu-sff.sh composite-margins 24 24 16 16` pulls all four edges inward. Increase the margin for an edge that is still cut off; decrease it if that edge has too much black border. Changes require a reboot.

## Status and uninstall

The status screen checks the backend recorded in the state file:

- native installations check `smbd.service` and `dnsmasq.service`;
- Docker installations check Docker and the `emu-samba` and `emu-dhcp` containers;
- full installations additionally check Wi-Fi, RetroArch, and CRT state.

Uninstall stops the selected backend, removes generated networking and application configuration, and restores the Samba configuration backed up by a native installation. It leaves the selected storage directory and game files in place. It does not uninstall Samba, dnsmasq, Docker, or RetroArch packages.

## Global launcher

If enabled during setup, the installer copies the application to `/usr/local/lib/emu-sff` and creates `/usr/local/bin/emu-sff`. The wrapper obtains root access with `sudo`, launches the utility in a transient `systemd-run --pty` unit, and returns to the same terminal when it exits.

After changing this checkout, update that installed copy with:

```bash
sudo ./emu-sff.sh refresh
```

## Repository structure

- [`emu-sff.sh`](./emu-sff.sh): main CLI and interactive menu
- [`lib/common.sh`](./lib/common.sh): shared defaults, UI, template rendering, and persisted state
- [`lib/setup.sh`](./lib/setup.sh): unified setup, backend migration, and CRT generation
- [`lib/status.sh`](./lib/status.sh): backend-aware status checks
- [`lib/uninstall.sh`](./lib/uninstall.sh): generated-file and managed-service cleanup
- [`templates/`](./templates): Samba, dnsmasq, Docker Compose, Netplan-related, systemd, and RetroArch templates

## Validation

The shell scripts and rendered configuration can be checked on any machine. Networking, Docker, systemd, DHCP, SMB, and CRT output must be validated on the target Linux hardware and real display chain.
