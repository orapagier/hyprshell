# Fedora Everything port

This port targets **Fedora Everything 44, x86_64, installed as a traditional
DNF system**. Start with the Everything network installer and a minimal
installation, a normal user with sudo access, and working networking.
Hyprshell installs the desktop after Fedora is installed; it does not
partition disks or install Fedora. It detects hardware to select firmware,
microcode, Mesa/Intel media support, and driver modules for a Fedora kernel.
Custom kernels are preserved and flagged for module review. Proprietary NVIDIA drivers,
Secure Boot signing, and unusual hardware still require device-specific checks. Fedora Atomic,
Silverblue, Kinoite, bootc, and OSTree installations are outside this port.

The desktop payload is shared with Arch: Hyprland Lua configuration,
Quickshell bar and Settings, menus, notifications, wallpaper helpers,
application preferences, and backup/sync workflows. Fedora has separate
package manifests and DNF package operations. Existing display managers
are preserved and enabled for graphical login. SDDM is installed only if none is found.

## Install from a Fedora TTY

Connect to the network first. On a minimal system, install the tools needed
to clone and run the installer:

```bash
sudo dnf install git python3 sudo
mkdir -p ~/repos
git clone https://github.com/orapagier/hyprshell.git ~/repos/hyprshell
cd ~/repos/hyprshell
./setup.sh --dry-run
./setup.sh
```

Use the repository/fork containing this port until it is published upstream.
Run setup as your desktop user, without `sudo ./setup.sh`. `--extra` adds
Distrobox, Podman and cmatrix. Everyday apps, archive tools, clipboard-history
tools, media controls and a text editor are included without it. The base manifest installs
the desktop, Chromium, terminal, file manager, Wi-Fi support, Bluetooth,
audio, fonts, helper build dependencies, Hyprlock, XDG utilities, clipboard
tools, Loupe, Papers, mpv, File Roller, rsync, htop, Déjà Dup, Restic,
rclone, and yt-dlp. Saved preferences enable Hyprlock after 60 idle minutes and before sleep.
Backup destinations/schedules must be configured separately after installation.
Clipboard capture remains disabled. [Daily-driver setup](daily-driver.md) covers
printing, scanning, keyring login, time sync, firewall, firmware and readiness checks.
Timezone is preserved unless `--timezone REGION/CITY` is supplied.

Full Fedora setup enables the third-party `lionheartp/Hyprland` COPR by default
to supply the compatible desktop ecosystem. Review this choice with `--dry-run`.
Use `--copr OWNER/REPO` to choose a different repository, or `--no-copr` to
preserve only the repositories already enabled. Config-only never changes repositories. [Hyprland's installation guide](https://wiki.hypr.land/Getting-Started/Installation/)
lists `lionheartp/Hyprland` for Fedora. Its [Fedora 44 build](https://copr-be.cloud.fedoraproject.org/results/lionheartp/Hyprland/fedora-44-x86_64/10966333-hyprland/)
provides Hyprland 0.56.2 and the separate `hyprland-uwsm` session package
(checked 2026-10-12). Repository builds change; the installer requires
Hyprland **0.56 or newer**, because older releases cannot load this Lua
configuration. Use compatible packages from one maintained ecosystem;
review repository conflicts in DNF instead of forcing package erasure.

If compatible repositories are already enabled, disable automatic COPR enablement:

```bash
./setup.sh --dry-run --no-copr
./setup.sh --no-copr
```

The installer first resolves/downloads the complete package transaction,
then upgrades Fedora and installs the desktop dependencies. Missing
packages or dependency conflicts stop the installation. SDDM, when needed, is
part of this preflight transaction. GPU/audio/wireless firmware is explicitly
listed because DNF weak dependencies are disabled. It never uses
`--allowerasing`, `--skip-unavailable`, disables signature checks, or turns
off SELinux. A dry run reads the installed RPM database, CPU/PCI/USB inventory and
service state; it does not enable repositories, refresh DNF metadata, download
packages, or copy files. From an Arch checkout, preview Fedora explicitly:

```bash
./setup.sh --distro fedora --dry-run --extra --copr lionheartp/Hyprland
```

After setup, reboot and select **Hyprland (uwsm-managed)**. From a TTY:

```bash
uwsm start -e -D Hyprland hyprland.desktop
```

## Distribution differences

| Concern | Fedora implementation |
| --- | --- |
| Core packages | `packages-fedora.txt` |
| Opt-in applications | `packages-apps-fedora.txt` |
| Wi-Fi | `NetworkManager-wifi`, NetworkManager, wpa_supplicant |
| Connection editor | `nm-connection-editor-desktop` |
| Audio | PipeWire, `pipewire-pulseaudio`, WirePlumber |
| Spectrum helper | `pulseaudio-libs-devel`, `fftw-devel`, `fftw-libs-double`, GCC |
| Power profiles | Fedora's `tuned` / `tuned-ppd` service, controlled directly over D-Bus |
| Icons | Adwaita, with bundled GoMono Nerd Font glyphs |
| Qt test runner | Qt 6 runner discovery; Fedora's `qmltestrunner-qt6` is supported |
| Login | Qt 6 SDDM and `sddm-x11` on a minimal install |
| Boot splash | Plymouth script plugin and dracut |
| Settings updates | Unprivileged DNF5 check; interactive `sudo dnf upgrade --refresh` |
| Optional tools | DNF install, including Fedora's `sane-backends` name |
| GitHub authentication | Fedora `gh` package |

The GoMono regular font and license notices are installed into
`${XDG_DATA_HOME:-$HOME/.local/share}/fonts/hyprshell`. It supplies the
glyphs used by the shell without relying on Arch's `ttf-go-nerd` package
or downloading a font during setup. Pop icon lookups fall back to Adwaita
on Fedora. Existing saved display settings and application IDs still
need review for the target laptop. Missing application IDs are skipped
by the shared preference restoration workflow.

## Boot and login appearance

Full Fedora setup installs Hyprshell Glass for SDDM and Plymouth.
`--skip-login-theme` and `--skip-boot-splash` leave those settings alone.
The Fedora splash installer supports ordinary `/boot/vmlinuz-*` /
`/boot/initramfs-*.img` pairs and Fedora BLS entries. It backs up changed
theme and dracut configuration, then runs:

```bash
sudo dracut --regenerate-all --force
```

The appearance installers restore SELinux file contexts with `restorecon`
before using the custom SDDM theme or rebuilding Fedora's initramfs.

Existing kernel arguments, disk/encryption IDs, and BLS entries are
preserved. Fedora's graphical boot needs `rhgb`; if you intentionally
removed it, review your kernel arguments and add it with Fedora's
`grubby` tooling if desired. Custom UKI and bootloader layouts keep their existing boot appearance
when detected as unsupported; integrate Plymouth manually if desired.
`--skip-boot-splash` skips all boot appearance work explicitly. This path does not
install Arch's UKI bitmap or use mkinitcpio.

Preview splash changes separately, once dependencies are installed:

```bash
python3 tools/install_boot_splash_fedora.py --dry-run
sudo python3 tools/install_boot_splash_fedora.py
```

On rebuild failure, changed configuration files are restored; generated
initramfs images may already have changed. Resolve the error and complete
the reported dracut rebuild before rebooting. Rescue images are not
treated as ordinary desktop kernel targets.

## Updates and validation

Settings chooses DNF on Fedora and pacman on Arch. Fedora update checks
use DNF5's JSON output and exit status 100 for available updates; see
the [DNF5 check-upgrade documentation](https://dnf5.readthedocs.io/en/latest/commands/check-upgrade.8.html).
Package installation and upgrades ask for the user's password in Kitty.
Fedora release upgrades remain a separate workflow; review COPR support
for the new release before performing one.

The development machine is Fedora 44. Validation includes isolated config
installs, mocked Fedora transactions, recovery tests and offscreen Qt checks.
The Fedora 44 CI job installs the native manifest and checks Lua/QML; this is
not a boot test. **A fresh Fedora Everything VM installation and physical
acceptance remain pending.** See [acceptance.md](acceptance.md).

On the target Fedora system:

```bash
python3 tools/check_runtime.py --native
Hyprland --verify-config --config "$PWD/config/hypr/hyprland.lua"
QT_QPA_PLATFORMTHEME= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  "$(python3 tools/check_runtime.py --qmltestrunner)" -input config/quickshell/tests
python3 -m unittest discover -s tests -p 'test_fedora.py' -v
```

Then verify an actual UWSM login, the bar/launcher, authorization prompts,
Wi-Fi, Bluetooth, output/input audio, brightness, lock/unlock, suspend,
portals, and SDDM/Plymouth on the target hardware. Configure GPU drivers
using Fedora and Hyprland's instructions for that device.

## Preserved settings and GitHub updates

Ordinary setup/update keeps existing preferences. Fresh users receive the
author’s personal configuration from the single `config/` payload.
Use the Settings header's **Sync from GitHub** to review incoming changes and
compatibility before applying. [Updates and recovery](updates.md) documents
tracking branches, dependency checks, local conflicts, backups and rollback.
`compatibility.json` is the support record; versions newer than its recorded
baseline need validation rather than an assumption of compatibility.
