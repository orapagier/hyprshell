# Observed local machine

Inspected 2026-10-09. These facts describe ramlej's machine, not every Hyprshell installation. Versions and preferences are snapshots; verify only those relevant to the request.

- User home `/home/ramlej`; checkout `/home/ramlej/repos/hyprshell`; state repository pointer confirms it. Default XDG paths currently contain the installed files.
- Arch Linux x86_64; kernel `7.2.9-arch1-1`; installed Hyprland `0.56.2-4`, Quickshell `0.3.2-1`, UWSM `0.27.0-1`.
- Intel Core i5-1235U (10 cores, 12 threads); integrated Alder Lake Iris Xe; about 16 GiB RAM and 4 GiB swap. Intel CNVi Wi-Fi and Intel PCH audio.
- Main monitor config uses preferred/auto; `hyprland-gui.lua` overrides eDP-1 to 1920×1080 at 60.01 Hz, scale 1, position 0x0, sRGB. This was verified in files, not via live monitor IPC.
- `/etc/systemd/system/display-manager.service` points to SDDM. Hyprland startup launches the bar through UWSM, hyprpolkitagent, and the wallpaper helper.
- Boot splash configured 2026-10-10: Plymouth `script` Arch logo theme, `plymouth` after `udev` in mkinitcpio hooks, and `quiet splash loglevel=3` in `/etc/kernel/cmdline`. The Linux preset generates a UKI at `/boot/EFI/Linux/arch-linux.efi`. User reported a successful rebuild; appearance awaits reboot verification. No disk identifiers belong in the saved splash preference.
- Glass splash activation verified in files 2026-10-10: `/etc/plymouth/plymouthd.conf` selects `hyprshell`, and installed theme assets match the repository. User likes its animated appearance. Reboot handoff has not been independently observed.
- Boot manager confirmed by user-provided `bootctl status` 2026-10-10: systemd-boot `262-1-arch` with systemd-stub `262-1-arch`, Secure Boot disabled, active UKI. User explicitly wants systemd-boot and its menu left unchanged. Do not propose or perform a bootloader migration for appearance changes.
- Matching login and UKI splash configuration verified in files 2026-10-10: `/etc/sddm.conf` selects `hyprshell-glass`, installed SDDM assets and `/usr/share/hyprshell/uki-splash.bmp` match the repository, and the active Linux preset uses `--splash /usr/share/hyprshell/uki-splash.bmp`. These checks confirm installed files and preset configuration, not the contents of the generated UKI or an observed reboot handoff.
- Kitty terminal, Nautilus file manager; Super release opens launcher; Super+B invokes Firefox (the default browser). Super+W / Super+Shift+W cycle wallpaper. Print and Insert both screenshot because this keyboard's Print emits Insert.
- Wallpaper startup selects `$HOME/Pictures/Wallpapers/default.jpg` through awww.
- Saved locking: enabled, `hyprlock`, 60 idle minutes, before sleep. Confirm current settings before changing locking.
- Saved bar: adaptive colors on, height 32, top margin 5, side margin 10, spacing 3; individual item preferences remain in settings.json.
- Native dependency checker passed. This inspection could not access Hyprland IPC or system/user D-Bus from the agent sandbox; running service status, active display state, and actual locking behavior were not verified.

Do not infer hostname, disk layout, active radios, service health, or current package versions from this profile. Use narrow live queries when needed. Keep serial numbers, MAC addresses, network names, tokens, and private history out of this file.

- 2026-10-12: Current OS verified as Fedora 44. Repository and live Super+E command now use `uwsm app -- cosmic-files`; saved folder default is `com.system76.CosmicFiles.desktop`. COSMIC Files was not installed at this check; package installation and compositor reload require the user terminal because this agent cannot elevate or access Hyprland IPC. Earlier Arch observations above are historical.

- 2026-10-12: Current OS verified as Fedora 44. Repository and live Super+E command now use `uwsm app -- cosmic-files`; saved folder default is `com.system76.CosmicFiles.desktop`. COSMIC Files was not installed at this check; package installation and compositor reload require the user terminal because this agent cannot elevate or access Hyprland IPC. Earlier Arch observations above are historical.
