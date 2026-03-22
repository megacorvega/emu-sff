<div align="center">

  <img src="./assets/emu-sff-icon.svg" alt="Emu Badge" width="150">

  <h1>emu-sff</h1>

  <p>Setup utility for emulation, built with sff PCs in mind.</p>

</div>

`emu-sff` configures one Linux machine to handle three jobs:

1. Serve legacy ROMs over Ethernet with an isolated DHCP + SMB stack.
2. Keep Wi-Fi performant for inbound game-file transfers.
3. Launch RetroArch against a CRT-friendly 15 kHz super resolution pipeline.

The repo is now organized so [`emu-sff.sh`](/Users/dd/emu-sff/emu-sff.sh) stays the main entrypoint and delegates to focused modules under [`lib/`](/Users/dd/emu-sff/lib) and reusable templates under [`templates/`](/Users/dd/emu-sff/templates).

The active install state is persisted at `/etc/emu-sff/emu-sff.env` so `status` and `uninstall` can find the configured paths and CRT settings without re-entering everything.

## Structure

- [`emu-sff.sh`](/Users/dd/emu-sff/emu-sff.sh): main CLI entrypoint.
- [`lib/common.sh`](/Users/dd/emu-sff/lib/common.sh): shared helpers, defaults, template rendering, and persisted state handling.
- [`lib/setup.sh`](/Users/dd/emu-sff/lib/setup.sh): interactive setup flow.
- [`lib/status.sh`](/Users/dd/emu-sff/lib/status.sh): service and config checks.
- [`lib/uninstall.sh`](/Users/dd/emu-sff/lib/uninstall.sh): generated-file cleanup.
- [`templates/`](/Users/dd/emu-sff/templates): auditable config templates for Docker, systemd, `xrandr`, and RetroArch.

## CRT path

The CRT workflow assumes:

- Debian/Ubuntu on X11.
- A GPU/driver stack that accepts custom `xrandr` modelines.
- A physical converter chain that can safely accept a 15 kHz signal.

During setup, the script generates these user-level files for the selected desktop user:

- `~/.config/emu-sff/apply-crt-mode.sh`
- `~/.config/emu-sff/crt-safety.conf`
- `~/.config/emu-sff/arm-crt-output.sh`
- `~/.config/emu-sff/disarm-crt-output.sh`
- `~/.config/emu-sff/retroarch-crt.cfg`
- `~/.config/emu-sff/launch-retroarch-crt.sh`
- `~/.config/systemd/user/emu-sff-crt-mode.service`

The default target mode is `2560x240_60.00` with this modeline:

```text
50.00 2560 2720 2960 3200 240 244 246 261 -hsync -vsync
```

That is a conservative starting point for a 15 kHz super resolution workflow, not a guarantee for every GPU, converter, or CRT. If your chain needs different porch/sync timings, edit the generated CRT mode script after setup.

## CRT safety gate

The CRT path is intentionally disarmed by default:

- setup generates the user service, but does not enable it
- `launch-retroarch-crt.sh` refuses to start if the CRT path is disarmed
- `apply-crt-mode.sh` refuses to touch the output unless:
  - `CRT_ARMED=1` in `~/.config/emu-sff/crt-safety.conf`
  - the configured modeline computes to a horizontal/vertical sync window that looks 15 kHz-safe

Arm and disarm helpers are generated so you can explicitly control when the CRT path is allowed to drive the display.

This mitigates accidental mode switches caused by this project, but it cannot control firmware, bootloader, display manager, or desktop modes that happen before the user-level scripts run. For first bring-up, keep the CRT disconnected or behind a known-safe switch until the Linux session and modeline are verified.

## Setup

Run the setup script as root:

```bash
chmod +x emu-sff.sh
sudo ./emu-sff.sh setup
```

Setup prompts for:

- LAN interface
- WLAN interface
- storage path
- generated-config path
- desktop user
- CRT output name
- super resolution width/height
- `xrandr` mode name and modeline

The setup flow can perform five independent steps:

1. Install Docker, RetroArch, `xrandr` tooling, and Wi-Fi utilities.
2. Configure a static `192.168.2.1/24` address on the LAN interface.
3. Disable Wi-Fi power saving with a persistent systemd service.
4. Generate and start the Samba + dnsmasq container stack.
5. Generate CRT/RetroArch scripts and a user service for mode application.
6. Optionally install `/usr/local/bin/emu-sff`, which launches the utility from anywhere using `sudo` plus `systemd-run --pty`.

If you later change the repo and want to refresh the installed global launcher bundle without rerunning setup, use:

```bash
sudo ./emu-sff.sh refresh
```

## Status and uninstall

Check the current state:

```bash
sudo ./emu-sff.sh status
```

Remove generated configuration:

```bash
sudo ./emu-sff.sh uninstall
```

## Global launcher

If you enable the launcher step during setup, the installer copies the main script to:

- `/usr/local/lib/emu-sff/emu-sff.sh`

and installs a wrapper at:

- `/usr/local/bin/emu-sff`

That wrapper:

- prompts for `sudo` when needed
- starts the utility in a transient systemd unit with `systemd-run --pty`
- returns you to the same terminal when the utility exits

## Testing notes

This repository can be syntax-checked on any machine, but the networking, Docker, systemd, and CRT mode portions need validation on the target Linux box with the real display chain attached.
