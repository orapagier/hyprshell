# Daily-driver installation

On an installed x86_64 Arch or traditional Fedora Everything 44 system with a
normal sudo-enabled user and working internet, run:

```bash
./setup.sh --dry-run
./setup.sh
```

Fedora enables `lionheartp/Hyprland` by default, the COPR listed in
[Hyprland's installation guide](https://wiki.hypr.land/Getting-Started/Installation/).
Use `--copr OWNER/REPO` to select another compatible ecosystem or `--no-copr`
to use only existing repositories. A preview does not query remote availability;
the full Fedora installer resolves/downloads the entire transaction, including
SDDM when needed, before upgrading or replacing desktop configs. Arch upgrades
and installs in one pacman transaction. Neither path forces package erasure.

`--extra` adds only Distrobox, Podman and cmatrix. `--config-only` updates
desktop files while retaining current preferences. `--update` additionally runs
compatibility and staged native checks. Fresh installs receive the author’s
personal configuration; updates preserve existing preferences. See
[updates.md](updates.md) and [acceptance.md](acceptance.md).

## Included without extra flags

| Area | Installed/prepared |
| --- | --- |
| Desktop | Hyprland 0.56+, UWSM, Quickshell, portals, Polkit agent, fonts, wallpaper and screenshots |
| Audio | PipeWire, PulseAudio/ALSA compatibility, WirePlumber, general audio and SOF firmware |
| Network | NetworkManager, Wi-Fi backend, connection editor, wireless firmware and BlueZ |
| Apps | Chromium, COSMIC Files/GVfs/MTP, Kitty, mpv, Loupe, Papers, Mousepad, File Roller |
| Integration | Browser/folder/media/image/PDF/text defaults, media keys, Wayland clipboard, archive tools, manuals and shell completion |
| Lock/power | Hyprlock artwork, Hypridle, brightness and power profiles; personal defaults or retained user locking preferences |
| Peripherals | CUPS socket, Avahi discovery, printer configuration, SANE and Simple Scan |
| Credentials | GNOME Keyring and Seahorse; optional SDDM PAM unlock where missing |
| Maintenance | CPU microcode, Chrony unless another time service is configured, firewalld unless another firewall service is configured, weekly fstrim |
| Recovery | Config backups, rsync, Déjà Dup, Restic, rclone and yt-dlp; backup destinations/schedules remain user choices |

Audio/video defaults use `mpv.desktop` on both distributions. The rest of the
saved application IDs are resolved against installed desktop entries; Chromium's
different distro IDs are handled by the preference restoration backend.
Clipboard history tooling is installed, but capture stays disabled until enabled
in Settings. Notification popups retain the saved preference (disabled); the
notification inbox remains available.

When a present laptop battery reaches 25% or below while unplugged, its bar icon
and percentage pulse and Hyprshell plays one short alert tone through the default
audio output (respecting mute and output volume). Plugging in stops the pulse.
The tone is armed again after connecting power or recovering above 30%; small
percentage fluctuations do not repeat it. This uses existing UPower updates and
does not control battery charging. Charge limits require firmware and kernel
support for the particular laptop.

## Existing systems

Setup preserves the selected login manager and enables it for graphical login.
If none is installed, SDDM is included in the package transaction. A broken
display-manager alias stops setup before package/config changes instead of
silently leaving graphical login unusable. It does not restart a live greeter.

An enabled or active time-sync/firewall alternative is retained. Existing
firewalld zones are never reset or reloaded. A newly enabled firewalld without
administrator zone files gets mDNS discovery enabled in its default zone for
network printers. CUPS is socket-activated; printer sharing is not enabled.
Manufacturer-specific printer/scanner drivers may still be required.

Optional GNOME Keyring PAM lines are added only to SDDM, without replacing its
authentication stack. Changed PAM files are backed up in
`/var/lib/hyprshell/system-backups/`. Password login can unlock a matching login
keyring; autologin, fingerprint-only login and TTY sessions may require a keyring
password prompt. No passwords or keyring files are saved in the repository.

The base monitor configuration uses preferred resolution, automatic positioning
and automatic scaling. Per-machine changes belong in Settings → Displays.
Previously saved display preferences still need review on different hardware.

## Hardware and first login

Arch installs the default `linux-firmware` set, SOF/ALSA firmware, Intel and AMD
microcode, and Mesa Vulkan drivers. Fedora explicitly installs the common split
wireless/GPU/audio firmware and kernel modules: these cannot be left to weak
dependencies because setup disables weak-dependency installation. Firmware
updates are files for kernel drivers, not BIOS flashing. Reboot to use updated
kernel modules, firmware and early CPU microcode. Existing custom bootloader
entries may need microcode/initramfs integration checked separately.

Mesa supports the normal Intel/AMD path and supported Nouveau hardware.
Existing proprietary NVIDIA installations are preserved; setup does not guess
a proprietary driver branch, replace the GPU stack, sign modules, or change
Secure Boot. The readiness report flags NVIDIA for review against
[Hyprland's NVIDIA instructions](https://wiki.hypr.land/Nvidia/).
Unsupported Wi-Fi adapters, vendor drivers, custom kernels, firmware defects,
and suspend quirks still require the target hardware to be tested.

Full Fedora setup enables RPM Fusion free/nonfree and installs
`libavcodec-freeworld`, the full Intel `intel-media-driver` (iHD), and
`libva-utils`. It replaces installed restricted `libavcodec-free` and
`libva-intel-media-driver` counterparts with targeted DNF swaps, without broad
`--allowerasing`, and verifies FFmpeg exposes an HEVC decoder. Arch includes
FFmpeg, Intel media-driver and libva-utils in its base manifest. mpv uses
`hwdec=auto-safe` with automatic software fallback; no Intel driver environment
variable is forced on other GPUs. Existing mpv config conflicts use the normal
deployment review. GitHub sync captures the managed mpv file.

To add only media support to an existing traditional Fedora desktop, run as
your normal user from the checkout:

```bash
bash tools/install_media_fedora.sh
vainfo
```

Restart media applications afterward. An installed driver or a software decoder
does not prove a browser is using GPU decoding; check its own media diagnostics.
Config-only updates do not install packages or enable repositories.

The canonical personal setup locks after 10 idle minutes, dims after 5 minutes,
turns the screen off after 15 minutes on AC / 10 on battery, and suspends after
30 minutes on AC / 20 on battery. Existing preferences remain preserved during
ordinary updates. Power-menu actions use `Alt+P`, then `L` (lock), `S` (sleep),
`R` (reboot), `X` (shutdown), or `O` (logout); Alt may remain held. Action keys
are enabled only while that menu is pinned open, including when a button has
focus. Release Alt before the action letter to avoid compositor shortcuts such
as Alt+S (Settings). Keyboard-opened power menus stay pinned when the pointer
leaves; Escape or an outside click dismisses them. Action handling includes raw
overlay keys when Qt shortcut activation is unavailable. `Super+L` locks directly. Lock-before-sleep remains enabled in the saved
personal setup. Automatic personal-file backups remain opt-in.

Setup saves a local, redacted report at
`~/.local/state/hyprshell/setup-readiness.json` (respecting XDG_STATE_HOME).
After reboot and a UWSM Hyprland login, run from the retained checkout:

```bash
python3 tools/check_daily_driver.py --after-login
```

This checks service states, tools, graphics-driver presence, actual audio devices,
Wi-Fi/Bluetooth adapter presence, and compositor configuration errors. Missing
hardware is marked for attention, rather than reporting a dummy audio device as
ready. Device names, Bluetooth addresses, network names and raw command errors
are not written to the report. Inaccessible services in a sandbox are reported
as unavailable. A TTY/install check cannot prove the next graphical login works.

Test speaker playback and microphone recording, Wi-Fi connection, Bluetooth
pairing, Lock now and password unlock, before-sleep lock, lid/suspend/resume,
browser playback, file opening, removable media, printer discovery and portal
screen sharing. Backup accounts/destinations, network passwords and paired
devices are intentionally configured on the destination machine.

Boot appearance is independent of desktop readiness. Unsupported boot layouts
are skipped before writing files (splash helper exit status 10). An actual write
or initramfs rebuild failure is fatal and must be resolved before rebooting.
Use `--skip-boot-splash` to avoid boot appearance work altogether.

## Validation boundary

Python tests exercise isolated fresh-home installs and mocked Arch/Fedora
transactions, service preservation, optional PAM changes, redaction, and boot
rollback. CI installs both native manifests in distro containers and checks
Lua/QML. These checks do not emulate a display manager boot or physical hardware.
Fresh Arch and Fedora boot/login testing remains required on supported target
hardware before claiming universal readiness.

Validation for the 2026-10-13 installer change: 245 backend/installer checks
passed, an additional PAM write-failure check passed, all 155 offscreen QML
checks passed, and Hyprland accepted the Lua
configuration. Native Quickshell process integration could not be validated
because the development sandbox denied IPC sockets; a bootable VM and sudo
were also unavailable. No full package transaction or fresh OS boot was run.
