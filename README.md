# Hyprshell

Hyprshell is a configurable desktop shell for **Hyprland on Arch Linux and
Fedora**, built with **Quickshell and Qt 6**. It brings application launching,
window and workspace controls, status menus, notifications, and desktop settings
into one interface, with wallpaper-adaptive glass surfaces.

Choose the desktop layout that suits you:

- **Hyprpane** is the status and menu panel, with configurable items and groups.
- **Hyprdock** is a compact application dock with pins and running applications.
- **Hyprbar** is a classic taskbar combining application buttons and status controls.

All three support Top, Bottom, Left, and Right placement, monitor selection, and
workspace-specific visibility. Use them separately or combine two on different
edges of the same monitor/workspace. Existing `bar` settings and IPC names refer
to Hyprpane, which was formerly called hyprbar.

The repository includes the shell, editable Hyprland Lua configuration, desktop
utilities, boot/login themes, and an installer. Setup runs on an existing
**x86_64 Arch Linux or traditional DNF-based Fedora 44** system. It installs
packages and desktop integration; it does not partition disks or install an
operating system or bootloader. Fresh installations start with the saved
configuration in this checkout. Ordinary updates preserve existing preferences.

Hyprshell uses one **rolling** update channel. Supported platforms, dependency
minimums, and recorded version evidence are in
[compatibility.json](compatibility.json); see the
[rolling support policy](docs/updates.md#rolling-support-policy).
For Fedora-specific repositories, package setup, and dracut integration, see
[the Fedora guide](docs/fedora.md). For services and hardware checks, see
[daily-driver setup](docs/daily-driver.md).

## Contents

- [Screenshots](#screenshots)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Installing alongside an existing desktop](#installing-alongside-an-existing-desktop)
- [Fedora installation](docs/fedora.md)
- [How Hyprshell works](#how-hyprshell-works)
- [First login and machine-specific configuration](#first-login-and-machine-specific-configuration)
- [Using the desktop](#using-the-desktop)
- [Keyboard and mouse shortcuts](#keyboard-and-mouse-shortcuts)
- [Customizing Hyprshell](#customizing-hyprshell)
- [Screen locking](#screen-locking)
- [System cleanup](#system-cleanup)
- [Saving your setup to GitHub](#saving-your-setup-to-github)
- [Updating, backups, and restoring files](#updating-backups-and-restoring-files)
- [Troubleshooting](#troubleshooting)
- [Project structure and references](#project-structure-and-references)

## Screenshots

<!-- desktop-screenshots:start -->
Captured from a running Hyprshell desktop.

### Hyprshell desktop and Hyprpane

![Hyprshell desktop and Hyprpane](docs/assets/hyprshell-desktop.png)

### Hyprshell application launcher

![Hyprshell application launcher](docs/assets/hyprshell-launcher.png)

### Hyprshell desktop settings

![Hyprshell desktop settings](docs/assets/hyprshell-settings.png)

### Hyprshell tiled windows

![Hyprshell tiled windows](docs/assets/hyprshell-tiled.png)
<!-- desktop-screenshots:end -->

To capture the running desktop, launcher, settings, and tiled windows, run
`python3 tools/capture_desktop.py` from a terminal in your Hyprland session.
The helper gives you time to arrange each view, asks you to review the images,
then saves them in `docs/assets/` and updates this gallery.
To add or refresh only the tiled windows view, use
`python3 tools/capture_desktop.py --view tiled`; existing screenshots are retained.

## Features

| Component | What it provides |
| --- | --- |
| Boot appearance | Animated Hyprshell Glass Plymouth splash, plus matching static artwork for supported unified kernel images. |
| Login screen | Matching animated Glass SDDM theme with user, password, session, keyboard layout, and power controls. |
| Application launcher | Search installed desktop applications and launch them from the bar or Super key. |
| Panels | Hyprpane status/menu panel, Hyprdock app dock, and Hyprbar taskbar; four-edge layouts, monitor/workspace scopes, previews, and presets. |
| Apps and windows | Shared or separate pins, drag reordering, running-window grouping, window pickers, focus/close/move actions, and optional recoverable Show Desktop. |
| Workspace controls | Switch workspaces and hover for a miniature wallpaper/window preview without switching. |
| Media display | Playback information, a speaker-output spectrum (12 bars horizontally, 5 on side panels), and a Now playing hover preview. |
| Calendar | Date and time with a calendar menu; bundled holiday data covers the Philippines. |
| Notifications | Persistent inbox with search, expansion, dismissal, and clearing; optional popups configured in Settings. |
| Audio controls | Output/input selection, volume and mute, per-application volumes, a test tone, and an opt-in microphone meter. |
| Wi-Fi | NetworkManager integration for wireless connections. |
| Bluetooth | BlueZ integration with device controls and pairing prompts. |
| Battery | Charge and health information when available from the hardware. |
| System tray | Application-provided tray icons. |
| Power menu | Lock, sleep, logout, reboot, and shutdown actions. |
| Displays and projection | Saved output modes/scales/positions, Duplicate / Extend overlay, and Hyprview projection of the active window. |
| Settings | Searchable controls for panels, application appearance, window rules, displays, input, power, default apps, startup, shortcuts, accessibility, and region. |
| Shortcut overlay | Search every active Hyprland binding and scoped shell/terminal controls with `Super+K`, including mouse, media, submap and release details. |
| System controls | Screen locking, network profiles, firewall rules and website blocks, DNS configuration, and printing/scanning tools. |
| Maintenance and recovery | Reviewed cleanup, setup backup/restore, opt-in personal-file snapshots, system upgrades, diagnostics, and GitHub configuration sync. |

The interface and service bindings use QML and JavaScript. A small C helper
captures and analyzes audio for the spectrum; Python helpers handle settings
validation, installation, cleanup, and GitHub sync.

The installer disables NetworkManager's separate `nm-applet` tray icon with a
user autostart override in `config/autostart/nm-applet.desktop`. Hyprshell's
Wi-Fi menu uses NetworkManager directly. Other apps' autostart entries are
preserved.

Desktop configuration and its installation steps live together in this
repository. `setup.sh` installs the shell, themes and utilities, initializing
preferences only for new users. See [reviewed updates and profiles](docs/updates.md).

## Requirements

The supported installation targets and requirements are:

- An installed **x86_64 Arch Linux** or **traditional DNF-based Fedora 44** system.
  Fedora Workstation, desktop Spins, Server, and Everything use the same Fedora
  setup; Everything is not required.
- A normal user account with `sudo` access.
- Internet access and working package repositories for your distribution.
- **Hyprland 0.56 or newer**, using its Lua configuration API.
- Hyprland GUI utilities (`hyprland-guiutils`), installed by the setup script
  if missing.
- Quickshell 0.3.2+, UWSM 0.27.0+ and Qt 6, installed if missing.
- See [compatibility.json](compatibility.json) for supported systems, minimums
  and recorded baseline versions; newer versions are not automatically certified.
- Graphics drivers suitable for Hyprland.

The installer uses official Arch repositories and pacman on Arch, and DNF on
traditional DNF-based Fedora 44, regardless of edition or desktop Spin. Both
targets use x86_64.

Some modules depend on hardware: Bluetooth needs a supported adapter, battery
information needs a battery exposed by the system, and brightness controls need
a controllable backlight. Media information depends on application support.

## Installation

### 1. Get the repository

Install the checkout tools as your normal desktop user. On Arch Linux:

```bash
sudo pacman -Syu --needed git python
```

On Fedora:

```bash
sudo dnf install git python3 sudo
```

Then clone the repository on either distribution:

```bash
git clone https://github.com/orapagier/hyprshell.git
cd hyprshell
```

Keep this checkout after installation. You use it for updates, and the
installer records its location for GitHub sync.

### 2. Review the installation plan

```bash
./setup.sh --dry-run
```

The preview reports detected hardware, selected drivers, missing installed packages,
installation destinations, services, and timezone behavior without changing files
or installing packages. Python 3 is required for the read-only hardware checks. It does not
resolve remote package availability; full installation does. Review
the machine-specific defaults described below before using the supplied
Hyprland configuration.

### 3. Install the desktop

```bash
./setup.sh
```

Do not run the script with `sudo`. Run it as your normal user; it invokes sudo
for system operations when needed.

The installer:

1. Checks the operating system, architecture, CPU, PCI/USB hardware and installed
   packages, then selects the distro manifest and suitable hardware dependencies.
   Preserves the existing login manager, including SDDM in the package transaction
   only when no manager is installed.
2. Upgrades the system and installs desktop, daily-driver and firmware packages.
   Fedora first resolves/downloads the full transaction from compatible repositories.
3. Stages and validates desktop files, downloads pinned Hyprmonitor and Hyprmatrix
   release binaries and verifies their SHA-256 checksums, builds the other helpers,
   retains current preferences, and backs up changed managed files before deployment.
4. Enables networking, Bluetooth, user audio and graphical login; starts UPower.
5. Prepares printing/discovery, keyring login, time sync, firewall and SSD trim,
   preserving configured time-service/firewall alternatives.
6. Checks the native runtime, QML components and Hyprland configuration, then
   refreshes fonts and user directories.
7. Restores the Glass SDDM theme where applicable and the boot splash on supported
   existing layouts. Unsupported boot layouts retain their current appearance;
   actual initramfs rebuild failures stop setup.
8. Saves a redacted readiness report and provides the command for hardware checks
   after reboot/login.

### Prebuilt desktop apps

Hyprmonitor and Hyprmatrix install automatically without local Cargo builds.
Their release repository, tag, asset names, checksums and minimum glibc versions
are pinned in [app-releases.json](app-releases.json). These initial binaries target
Linux x86-64 with glibc 2.43 or newer.
The installer checks the host glibc before downloading either app. Fresh Arch
runtime acceptance remains pending; the binaries were built on Fedora 44.
An unchanged installed binary is reused after checksum verification. Missing
release assets, failed downloads or checksum errors stop deployment before live
files are replaced; installation never silently falls back to compiling these apps.
The audio helper and Hyprweather still build locally, so build dependencies remain
part of setup. Application settings, launchers and shortcuts are installed as before.

To publish desktop app updates, build both apps with `cargo build --release --locked`
using their respective `--manifest-path apps/<app>-rs/Cargo.toml`, then run:

```bash
python3 tools/package_desktop_apps.py --tag desktop-apps-v0.1.0 \
  --output "$HOME/Downloads/hyprshell-desktop-apps-v0.1.0"
```

The packager copies the executables under architecture-specific asset names,
generates `SHA256SUMS` and release notes, and updates `app-releases.json`. Upload
the two executables and `SHA256SUMS` to a GitHub Release in the manifest's repository
with exactly the specified tag. Use the generated notes as its description. Publish
the assets before distributing the installer changes that reference them. Use a
new tag for every binary update; commit the updated manifest alongside matching
source/config changes. Keep binaries out of Git. For other architectures or older
glibc hosts, build compatible assets and extend the manifest before enabling them.

### Whole-system planning

`setup.sh` builds one read-only [system plan](tools/system_plan.py) before any
sudo operation. `--dry-run` shows installed/missing dependencies for every
subsystem, plus the choices to install, preserve or review. Fedora reads installed
RPM packages and provider capabilities in one query; Arch checks dependency
providers with pacman. The package and service stages consume the same plan.

| Subsystem | What setup checks and decides |
| --- | --- |
| Session, portals and native libraries | Keep Hyprshell's required runtime and build dependencies; install missing providers and validate supported versions |
| CPU, graphics, audio and wireless firmware | Detect hardware and choose matching firmware/microcode/video packages; preserve custom kernels and proprietary drivers |
| Networking and audio services | Use NetworkManager and PipeWire/WirePlumber; stop before privileged changes if an exclusive network manager or legacy PulseAudio needs migration |
| Power and battery | Preserve configured or installed tuned, PPD, TLP, auto-cpufreq or System76 policies; use the distro default only when no existing power provider is found |
| Bluetooth and brightness | Detect adapters/backlights; retain hotplug tools, start Bluetooth only when an adapter is detected |
| Storage, time sync and firewall | Enable trim only for detected discard support; keep existing trim policy otherwise; preserve configured time/firewall alternatives and rules |
| Login, boot and security | Keep the login manager, bootloader, encryption options and authentication stack; install SDDM only if missing and honor appearance opt-outs |
| Apps, file integration, fonts and utilities | Use the shared desktop configuration and saved user choices; keep existing desktops and install the dependencies needed for those desktop functions |
| Printing, scanning and backups | Retain tools for local/network/hotplug peripherals; CUPS is socket-activated; backup schedules and clipboard capture remain opt-in |

This is dependency and compatibility planning across the whole installer.
Browser, file manager and font choices follow the desktop configuration and
saved preferences. Optional tools start according to their saved startup choices.
Conflicting backends stop installation for deliberate migration, preserving the
existing network, desktop and audio/power policies. See [TLP's guidance on competing power daemons](https://linrunner.de/tlp/faq/conflicts.html).

Inaccessible system-service/package checks are shown as unavailable and full
setup must be rerun from a normal system session. A TTY without a user D-Bus
session remains supported: installed audio packages are checked and user audio
services are enabled for the next login. Config-only updates skip system planning.

### Arch and Fedora feature parity

Both distributions install the same desktop payload and provide the same
Hyprshell features. Package names and system integration follow each distribution:

| Feature | Arch Linux | Fedora |
| --- | --- | --- |
| Bar, launcher, Settings, notifications, shortcuts, lock and wallpapers | Shared Hyprland/Quickshell configuration | Same configuration |
| Apps, printing/scanning, keyring, backups, clipboard tools and GitHub sync | Shared app selection and service planning | Same selection and planning |
| Firmware, microcode and GPU acceleration | Hardware-selected Arch packages, Mesa and FFmpeg | Hardware-selected Fedora packages and RPM Fusion codecs |
| Power profiles | power-profiles-daemon by default; preserve existing providers | tuned-ppd by default; preserve existing providers |
| Package management in setup and Settings | pacman | DNF |
| Glass login and boot appearance | SDDM and Plymouth with supported mkinitcpio layouts | SDDM and Plymouth with supported dracut layouts |
| Optional containers and terminal decoration | `--extra`: Distrobox, Podman, cmatrix | Same optional tools |

Both preserve existing desktops, login managers and user preferences, check
Hyprland compatibility before deploying configs, and verify H.264/HEVC software
decoders after full package setup. Boot layouts, proprietary drivers and actual
hardware behavior still need the checks described below; shared features do not
imply that every machine or desktop combination has completed acceptance testing.

### Hardware-aware packages and media support

Full setup includes media codecs and chooses acceleration packages from the
detected GPU, independently of the CPU vendor. It supports desktops, laptops
and hybrid graphics, selecting drivers for each machine.
[Hardware selection](tools/hardware_plan.py) reads kernel PCI/USB data
without collecting serial numbers, network names or device addresses.

| Detected hardware | Automatic selection |
| --- | --- |
| Intel CPU / AMD CPU | Matching microcode package; virtual CPUs leave microcode to the host |
| Known Broadwell-or-newer Intel GPU families | Intel iHD media driver; Intel Vulkan on Arch |
| Known older Intel GPU families | Legacy i965 media driver; software fallback for unsupported codecs |
| AMD GPU | Mesa graphics; Radeon Vulkan on Arch, Freeworld Mesa VA-API on Fedora |
| NVIDIA GPU | Preserve the current driver; Nouveau Vulkan on Arch only when Nouveau is detected; report proprietary-driver/Secure Boot review |
| Other, virtual or unidentified GPU | Keep Mesa and software codecs; report that acceleration needs review |

The general firmware package remains installed. Fedora's split firmware packages
are selected by detected PCI/USB vendors, with SOF firmware for Intel audio.
If the inventory is inaccessible, setup retains broad firmware coverage and reports
the limitation. Fedora kernel modules are selected for a detected Fedora kernel;
custom kernels retain their existing module setup and receive a review note.
Existing configured time-sync/firewall alternatives and an installed full Fedora
FFmpeg are preserved.

Fedora setup enables RPM Fusion free/nonfree, installs `libavcodec-freeworld`
**alongside** Fedora's codec package, and resolves selected media-driver
transactions before the system upgrade. Only conflicting Intel/Mesa acceleration
counterparts are swapped. Arch uses its distribution FFmpeg and GPU packages.
mpv defaults to `hwdec=auto-safe`, with software fallback. Both H.264 and HEVC
software decoders are checked during full setup on both distributions.

Installed packages/providers are checked first. Arch uses `--needed` with a full
system upgrade; Fedora rechecks after upgrading and installs missing dependencies.
Rerunning setup does not force reinstall already satisfied packages or remove
drivers belonging to other hardware. `--config-only` and `--update` skip package
and hardware selection. Full setup still upgrades the system even when every
desktop package is present.

Automatic selection follows supported driver families, not a universal performance
ranking. New/unknown GPU IDs, proprietary NVIDIA branches, Secure Boot, vendor
Wi-Fi drivers and printer drivers need review. Package installation does not prove
hardware decoding or suspend works: run `vainfo` in the desktop session and check
actual mpv/browser playback. See [Fedora's acceleration guidance](https://fedoraproject.org/wiki/Hardware_Video_Acceleration)
and [daily-driver checks](docs/daily-driver.md).

The base package list is in [packages.txt](packages.txt). It includes Flatpak (with Brave installed from Flathub by full setup),
Kitty, COSMIC Files with GVfs/MTP support (`gvfs-mtp`), UWSM, portals,
the Polkit agent, fonts and icons, screenshot and
brightness tools, NetworkManager, BlueZ, UPower, PipeWire, and WirePlumber.
It also includes Plymouth. See [boot splash setup and portability](docs/boot-splash.md)
for supported UKI, GRUB, and systemd-boot layouts and boot configuration backups.
The static UKI splash replaces the embedded Arch logo; systemd-boot's text menu
stays unchanged. See [login appearance](docs/login-appearance.md) for the matching
SDDM theme and a combined installer for an already configured machine.

Changed shared files are backed up. Conflicting local code edits stop deployment;
current preferences and unrelated files are retained. See [updates](docs/updates.md).
The installer preserves your timezone and existing login manager. If no login
manager is configured or detected as an installed service, it installs SDDM,
enables it for the next boot, and selects the graphical boot target.
It does not reboot the machine or restart the running desktop.

### Installing alongside an existing desktop

Hyprshell is designed to coexist with an existing desktop, including KDE
Plasma, GNOME, Xfce, Cinnamon, MATE, LXQt, or COSMIC, on a supported system.
The installer preserves existing desktops, their sessions and the login manager,
and installs SDDM only when none is found. At a login screen that supports Hyprland,
select **Hyprland (uwsm-managed)** to use Hyprshell, or select your existing
desktop to return to it. Log out before switching sessions. Hyprshell's bar,
launcher, and desktop controls run in the Hyprland session.

The installation limits remain x86_64 Arch Linux and traditional DNF-based
Fedora 44 across its DNF-based editions and Spins. Hyprshell can be installed
alongside any existing desktop environment; it runs as a separate Hyprland session.
Preservation of existing desktops is confirmed by installer/configuration
review; fresh coexistence tests for the desktops listed above are pending.
Identical behavior across desktops and hardware is not yet certified;
see [compatibility.json](compatibility.json) and [Fedora validation](docs/fedora.md).
Fedora Kinoite, Silverblue, and other Atomic/OSTree systems are unsupported.

Preserving a login manager does not guarantee that its greeter can list or
launch the Hyprland session. Check the upstream [Hyprland launch guidance](https://wiki.hypr.land/getting-started/master-tutorial/#launching-hyprland)
for current manager-specific limitations. If it cannot launch Hyprland, use the
TTY command under [Start a session](#4-start-a-session). The installer does not
replace that manager automatically to resolve launch compatibility. The Glass
login theme is applied only to SDDM; other login managers retain their appearance.

Full setup upgrades system packages, enables shared services, and applies the
SDDM theme and supported boot splash by default. To keep the existing login
and boot appearance, preview and install with:

```bash
./setup.sh --dry-run --skip-login-theme --skip-boot-splash
./setup.sh --skip-login-theme --skip-boot-splash
```

Some user preferences are shared across desktop sessions. A fresh Hyprshell
installation restores bundled default-app choices in `mimeapps.list` and can
update an existing desktop-specific defaults file for the desktop running the
installer. The managed `nm-applet.desktop` autostart override hides that applet
across sessions. These appearance flags do not prevent shared preference or
service changes; review application defaults and startup choices after setup.
In desktops that rely on `nm-applet` for their network tray, that override also
hides their network icon. Hyprshell's network menu is available only in its own
session.

### Boot and login appearance

The startup sequence uses a shared dark glass design with lavender/cyan
lighting and Hyprshell lettering. On a supported UKI installation, a static
matching image appears before Plymouth animates the title, glow, and boot
progress. SDDM then shows the animated login card. Plymouth also supplies
password prompts and shutdown artwork.

![Hyprshell Glass boot splash](docs/assets/boot-splash-preview.png)

![Hyprshell Glass login screen](docs/assets/login-preview.png)

Firmware logos and the existing bootloader menu remain machine-specific.
Plymouth and SDDM have separate animation clocks; graphics initialization can
cause a brief blank frame between them. Check the sequence after reboot on
each machine. The detailed [boot](docs/boot-splash.md) and
[login](docs/login-appearance.md) guides include previews, separate installers,
supported layouts, and recovery instructions.

### Installation options

| Option | Purpose |
| --- | --- |
| `--dry-run` | Preview the plan without making changes. |
| `--config-only` | Install configurations, utilities, and wallpapers, and compile the spectrum helper; skip package and service changes. |
| `--extra` | Also install Distrobox, Podman, and cmatrix from the optional distro manifest. |
| `--no-copr` | On Fedora, use only enabled repositories instead of enabling the default desktop COPR. |
| `--skip-boot-splash` | Leave system boot configuration unchanged. |
| `--skip-login-theme` | Leave the current login screen appearance unchanged. |
| `--timezone ZONE` | Set an explicit timezone, such as `Europe/London`. |
| `--keep-timezone` | Preserve the current timezone; this is the default. |
| `--help` | Show command-line help. |

Examples:

```bash
./setup.sh --extra --dry-run
./setup.sh --extra
./setup.sh --timezone Europe/London
```

Setup also installs Bash shortcuts while preserving your existing `~/.bashrc`:
`pcm package-name` runs `sudo pacman -S --needed package-name`; `fedora` and
`ubuntu` enter the matching Distroboxes. Other existing container names become
commands when you open a terminal, provided they do not conflict with an existing
command. After creating a container, run `hyprshell_refresh_boxes` or open a new
terminal. To load the shortcuts in an already open terminal, run `source ~/.bashrc`.
These shortcuts are also installed by `--config-only`.

The main setup and `--config-only` install Kitty's one-handed clipboard defaults:
Ctrl+V pastes text through Kitty, or forwards the key to the terminal application
when the clipboard offers an image so apps can attach it themselves.
Ctrl+C copies selected text or interrupts the running command
when nothing is selected. Editors retain their native Ctrl+C/V/X shortcuts.
Super+C/V clipboard forwarding is omitted to avoid stuck synthetic keys.
Tab completion remains available. Bash's default Emacs editing shortcuts remain
Ctrl+U to remove text before the cursor, Ctrl+K to remove text after it, and
Ctrl+Y to restore removed text; these use Bash's own buffer, not the desktop
clipboard. Terminal output can be copied, but cannot be cut.

The main install includes Hyprlock, XDG utilities and clipboard tools,
Loupe, Papers, mpv, File Roller, rsync, htop, Déjà Dup, Restic, rclone,
and yt-dlp, plus Mousepad, media controls, archives, clipboard-history tools,
printing/scanning, firmware, keyring support, time synchronization and firewall.
This checkout enables Hyprlock after 10 idle minutes and before sleep.
Clipboard capture stays disabled until enabled in Settings. Backup destinations
and schedules need to be configured after installation.

The optional [application list](packages-apps.txt) includes Distrobox, Podman,
and cmatrix. Everyday applications are included in the base installation.

`--config-only` requires Python 3, a C compiler, and the libpulse/FFTW development
files to be installed already. Use the full installer when dependencies are
missing.

### 4. Start a session

After installation, reboot and select **Hyprland (uwsm-managed)** in your login
screen. If you do not use a display manager, log in on a TTY and run:

```bash
uwsm start -e -D Hyprland hyprland.desktop
```

Use `Super+Z` to open a terminal with the saved shortcuts (`Super+T` in the
base configuration), and press and release `Super` to open the
application launcher. The Windows key is normally the Super key.

## How Hyprshell works

Hyprland handles window placement, workspaces, input, and compositor effects.
The entry point `~/.config/hypr/hyprland.lua` loads editable sections from
`~/.config/hyprshell/hyprland/`, then applies generated Settings overrides.
The supplied session uses UWSM to manage the session and application launches.

Quickshell loads `~/.config/quickshell/shell.qml`. One shell instance provides
the panels, launcher, menus, Settings, and notification service. The panels
share application discovery, window matching, pins, and desktop services rather
than starting separate app or notification services for each panel.

| Integration | Backend |
| --- | --- |
| Audio | PipeWire / PipeWire Pulse and WirePlumber; a native helper analyzes the speaker-output spectrum. |
| Network and Bluetooth | NetworkManager and BlueZ. |
| Battery and power | UPower and the installed supported power-profile provider. |
| Notifications | Hyprshell owns `org.freedesktop.Notifications` and stores inbox history locally. |
| Wallpaper | `awww`, with per-output wallpaper sampling for adaptive panel colors. |
| Locking | Hyprlock, with a Hypridle child managed by the shell when enabled. |
| Preferences | Versioned JSON, validated Python transactions, backups, and generated Lua where needed. |

Installed configuration files are **copies of the checkout**, not symlinks.
Settings changes apply to the installed configuration. Sync to GitHub captures
those changes into the checkout before committing and pushing them. Setup and
reviewed updates validate files and preserve preferences; there is no background
Git saver.

### Saved configuration in this checkout

The saved configuration is distinct from component fallback defaults. At the
time of this README update, both the checkout and installed preferences use:

| Preference | Saved choice |
| --- | --- |
| Panel layout | Hyprpane at the top on workspaces 1–4; Hyprbar at the bottom on workspace 5; Hyprdock at the bottom on workspace 6. All three master switches are enabled. |
| Appearance | Wallpaper-adaptive colors and random vibrant item colors enabled. |
| App pins | Shared Brave and COSMIC Files pins. |
| Locking | Hyprlock after 10 idle minutes and before sleep. |
| Notifications | Popups enabled for 3 seconds; Do Not Disturb off; critical bypass enabled. |
| Clipboard history | Capture disabled until enabled in Settings. |
| Shortcuts | Terminal remapped to `Super+Z`, Hyprpane toggle to `Alt+X`, and reload on `Alt+Q`. |

These are editable preferences, not requirements for using Hyprshell. Fresh setup
uses the checkout's saved values; existing installations retain their own choices.

## First login and machine-specific configuration

The supplied configuration is a starting point. Review these defaults for your
own hardware and preferences:

| Setting | Where to change it |
| --- | --- |
| Display resolution, refresh rate, scale, and position | Settings → Displays; underlying rules in `~/.config/hyprshell/hyprland/monitors.lua` and `hypr/hyprland-gui.lua`. |
| Keyboard layout | The `input.kb_layout` value in `~/.config/hyprshell/hyprland/input.lua`; bundled value is `us`. |
| Terminal and file manager | The `terminal` and `fileManager` entries in `~/.config/hyprshell/hyprland/programs.lua`. |
| Browser shortcut | `Super+B` uses `hyprshell-browser` to open the configured default browser; fresh setup provides Brave from Flathub. Change the default in Settings → Applications. |
| Startup wallpaper | `~/.config/hypr/wallpaper-start.sh`. |
| Clock display | Hyprshell Settings → Hyprpane & panels. |
| Holiday data | `~/.config/quickshell/Calendar.js`. |

New displays use an automatic preferred-mode, position, and scale rule. Confirm machine-specific choices
in **Settings → Displays**; Apply / Keep provides a 15-second rollback window.
Saved connector preferences override the automatic fallback. Inspect connected
outputs inside Hyprland with:

```bash
hyprctl monitors
```

After editing your installed Hyprland configuration, validate and reload it:

```bash
Hyprland --verify-config --config "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
hyprctl reload
```

Hyprshell installs the saved preferences in `config/hyprshell/settings.json`
when that file exists in the checkout. These can differ from the bundled
component defaults. Review the Settings window after your first login.

## Using the desktop

### Hyprpane and menus

Hover over a menu icon to open its menu, then move into the menu to interact
with it. Hovering another icon switches menus. Click an icon to pin its menu
open; another click, an outside click, or Escape closes it.

Menus follow their icons when you move or reorder modules, and stay within
screen edges. Some items appear only when relevant, such as the battery on
supported hardware or media information during playback.

### Applications and workspaces

Press and release Super, or click the launcher logo, to open the application
launcher. Type to filter applications by name and select an entry to launch it.
Applications are discovered through installed desktop entries.

Use workspace buttons or `Super+1` through `Super+0` to switch workspaces.
Hold Shift with those shortcuts to move the focused window to a workspace.
Regular application windows tile; the supplied rules float common dialogs and
file choosers.

### Hyprdock, Hyprbar, and app pins

Click an idle pinned app to launch it, a single-window app to focus it, or a
group to choose a window. Right-click an app for pin/unpin, new instance, close,
and workspace-move actions; middle-click opens another instance. Drag pins or
use Ctrl+arrow keys to reorder them. Overflow scrolls when the panel is full.

Right-click a launcher result, or select it and press `Ctrl+P`, to pin it.
**Apps & windows** manages shared or separate pin lists, running windows, and
explicit app matching when a window has the wrong identity. Hyprbar can group
windows and filter them by workspace and monitor. Its trailing status items can
inherit Hyprpane's selection or use their own list.

Enable **Show Desktop shortcut** in either app panel to hide and restore the
current workspace's windows. Recovery survives shell restarts; **Apps & windows →
Restore desktop windows** remains available if a restore needs retrying. The
`Super+H` / `Super+Shift+H` single-window shortcuts use a separate stack.

### Displays and Hyprview

`Super+P` opens a compact **Duplicate / Extend** overlay. Either choice applies,
saves, and closes the overlay. Use **Settings → Displays** for individual output
resolution, refresh rate, scale, position, rotation, and mirror sources.

`Super+V` projects the active window through **Hyprview**, without moving the
original window. It fills an enabled non-mirrored external display (HDMI is
preferred), or opens a floating viewer when only one screen is available. The
projection is view only. `Super+Shift+V` closes it from any screen; when the
viewer is focused, F11 toggles fullscreen and Escape leaves fullscreen or closes.

### Audio, networking, and Bluetooth

The audio menu provides volume and microphone sliders, mute controls, and
output selection. Sliders support clicking and dragging. Settings → Sound adds
per-stream volumes, input/output selection, an explicit microphone meter, and a
test tone. The visualizer captures the **speaker output monitor**, not microphone input.

The Wi-Fi menu uses NetworkManager. The Bluetooth menu uses BlueZ and handles
pairing prompts in the interface. Their availability depends on the relevant
services, hardware, and radio state.

### Notifications

Notifications remain available in the bell's inbox. **Settings → Notifications**
controls popups, Do Not Disturb, critical bypass, timeout, and per-app delivery.
This checkout enables popups; fallback component defaults leave them off. Click a
notification to expand its full title and body, scroll to read long messages,
and use its corner × to dismiss it. Search and Clear all are available.

History is stored through Quickshell at `Quickshell.statePath("notifications.json")`.
An older notification database, if present, can be imported once using read-only
SQLite access. Hyprshell preserves the message text supplied by applications;
it cannot recover text an application truncated before sending.

### Wallpapers

Put JPG, JPEG, PNG, or WebP images in `~/Pictures/Wallpapers`. Use `Super+W` for
the next wallpaper and `Super+Shift+W` for the previous one. The cycling script
uses a sorted list of files in that directory.

The supplied startup script selects `default.jpg` on login. Edit
`wallpaper-start.sh` to choose a different startup image. Wallpaper rendering
uses `awww`; bar colors adapt to the wallpaper on each output.

## Keyboard and mouse shortcuts

The table follows the saved configuration shipped in this checkout, including
its shortcut remaps. `Super+K` shows the active bindings on your installation.
The Windows key is normally Super.

| Shortcut | Action |
| --- | --- |
| `Super+Z` | Open Kitty (base binding: `Super+T`). |
| Press and release `Super` | Toggle the application launcher. |
| `Super+E` | Open a COSMIC Files window. |
| `Super+K` | Toggle the searchable shortcut overlay. |
| `Alt+X` | Toggle Hyprpane on the current workspace (base binding: `Alt+T`). |
| `Alt+D` / `Alt+Z` | Toggle Hyprdock / Hyprbar on the current workspace. |
| `Alt+S` | Open Hyprshell Settings. |
| `Alt+C` / `Alt+N` | Toggle calendar / notifications. |
| `Alt+A` / `Alt+W` | Toggle audio / Wi-Fi. |
| `Alt+V` / `Alt+B` / `Alt+P` | Toggle Bluetooth / battery / power options. |
| `Super+B` | Open the configured default browser. |
| `Super+Q` | Close the focused window. |
| `Super+M` | Toggle maximized mode. |
| `Super+V` / `Super+Shift+V` | Project the active window in Hyprview / close Hyprview. |
| `Super+Alt+V` | Toggle floating mode. |
| `Super+Arrow keys` | Move focus between windows. |
| `Super+Shift+Arrow keys` | Swap the active tiled window with its neighbor. |
| `Super+Alt+Arrow keys` | Move and retile the active window in that direction. |
| `Super+1…9`, `Super+0` | Switch to workspace 1…10. |
| `Super+Shift+1…9`, `Super+Shift+0` | Move the focused window to workspace 1…10. |
| `Super+Mouse wheel` | Switch to the next or previous workspace. |
| `Super+Left drag` | Move a window. |
| `Super+Right drag` | Resize a window. |
| `Super+P` | Open Duplicate / Extend display controls. |
| `Super+Shift+P` | Toggle pseudotiling. |
| `Super+J` | Toggle the split direction in the dwindle layout. |
| `Super+Ctrl+F` / `Super+Ctrl+S` | Toggle automatic floating / pseudotiling for the current workspace. |
| `Super+Ctrl+H` | Toggle hover popdowns for the current workspace. |
| `Super+L` | Lock the screen. |
| `Super+S` | Toggle the `magic` special workspace. |
| `Super+Shift+S` | Move the focused window to that special workspace. |
| `Super+H` / `Super+Shift+H` | Hide / restore a window. |
| `Super+W` / `Super+Shift+W` | Next / previous wallpaper. |
| `Print` or `Insert` | Select a screenshot region and open it in Swappy. |
| `F2` / `F3` | Lower / raise output volume. |
| `F4` / `F1` | Toggle output / microphone mute. |
| `F6` / `F7` | Lower / raise brightness. |
| Supported media and brightness keys | Control volume, playback, microphone mute, or brightness. |
| `Super+Shift+M` | End the Hyprland session. |

The saved shortcut customizations in this checkout also bind `Alt+Q` to reload
Hyprland, then Quickshell, so saved shortcuts and shell changes activate together.
Use `Super+K` to inspect active shortcuts after customizations. The
Alt menu shortcuts work while Hyprpane is hidden.

Playback keybindings use `playerctl`, included in the base installation. Brightness bindings depend on the system's backlight
support.

## Customizing Hyprshell

### Open Settings

Open **Hyprshell Settings** in the application launcher, or use the cog menu
on the bar and select **Open Hyprshell Settings**. From a terminal:

```bash
~/.local/bin/hyprshell-settings
```

The shell must be running. Use the search field to find controls across pages.
Settings opens inside the existing Quickshell process
and includes a preview with sample statuses. The preview's colors and visible
sample modules may differ from live hardware and wallpaper colors.

### Choose panels and workspace layouts

Open **Settings → Hyprpane & panels**. Each panel has an enable switch, edge,
monitor selection, and workspace visibility controls. Master enablement gates
all workspace choices. **Show on all** and **Hide on all** clear individual
choices; use the workspace selector and switch to make exceptions.

At most **two panels may be visible together on one monitor/workspace**, and
they must occupy different edges. All three can remain enabled globally when
workspace or monitor scopes separate them. Auto-hide panels still count toward
this limit. Invalid placements show an error and retain the last saved layout.

**Panel layout preview & presets** shows draft placement for a selected monitor
and workspace. Selecting a preset only previews it; **Apply layout preset**
changes enablement and edges together. Presets preserve appearance, pins, and
visibility scopes, so check whether a selected panel is hidden on that workspace.

For example, use **Hide on all**, then enable workspaces 1–4 for Hyprpane,
workspace 5 for Hyprbar, and workspace 6 for Hyprdock to reproduce the saved
layout. For a status panel plus app dock on every workspace, apply the
Hyprpane Top + Hyprdock Bottom preset (which disables Hyprbar), then choose
**Show on all** for both panels.

Hyprdock and Hyprbar offer **Always visible**, **Auto-hide**, and **Hide when
overlapped**. Always-visible panels reserve window space; the other modes do
not, and reveal from a 3 px screen-edge strip. Choose whether they hide in
fullscreen, then tune alignment, margins, thickness, icon size, spacing, inside
padding, indicators, and animations. Files, Settings, Trash, and Show Desktop
shortcuts are optional. Empty Trash requires confirmation.

### Layout and appearance

For Hyprpane, use the preview to select an item or drag it into the left,
center, or right group. You can reorder items, show or hide built-in modules, and adjust:

- Screen edge, height, margins, spacing, and clock format.
- Full-edge or compact presentation on side edges.
- Global and individual icon sizes from 8–48 px.
- Per-item text and icon glyphs, font size, and extra spacing.
- Text, icon, background, and outline colors using `#RRGGBB`.
- Item opacity, background opacity, pill visibility, and corner radius.
- Wallpaper-adaptive colors globally or per item.
- Random vibrant item colors that reshuffle when the wallpaper changes.

Individual overrides take priority over general settings. Choose inheritance
or use the relevant reset control to return to the general value. Manual colors
override the corresponding adaptive colors. Tray artwork remains supplied by
its application.

Avoid overcrowding the bar: unusually wide labels or too many center items can
overlap other groups. Shorten text, reduce sizes, hide items, or move them to
another group. Status services continue running when their bar items are hidden.

### Tune readability and responsiveness

Start with panel thickness, icon size, and spacing before changing individual
items. Side Hyprpane layouts use compact circular controls, with the first group
at the top and the last at the bottom. Move back to Top or Bottom to restore
horizontal labels and pill styling. Hover workspaces for window-layout previews
and the media spectrum for Now playing; captures run only while previews are open.

For a quieter desktop, disable notification popups or enable Do Not Disturb,
turn off hover popdowns on selected workspaces, and hide unneeded items.
Hiding an item does not stop its shared desktop service.

**Settings → Windows** controls compositor blur, shadows, opacity, gaps, and
animations. Reducing blur size/passes or disabling effects can reduce rendering
work. **Accessibility → Reduced motion** disables panel fades; text scale and
high contrast help readability. Display scale belongs in **Displays**, while
application font, cursor, and GTK appearance belong in **Appearance**.

### Tune applications and system behavior

| What to change | Settings page |
| --- | --- |
| Default browser, file associations, and apps started at login | Applications; startup choices take effect next login. |
| Per-workspace floating/pseudotiling and app-specific rules | Workspaces & rules. |
| Touchpad, scrolling, pointer, and keyboard behavior | Mouse & keyboard. |
| Dimming, screen-off, sleep, lid action, and AC/battery policies | Power & battery. |
| Hidden Wi-Fi and saved profiles; advanced VPN/IP configuration | Network; advanced editing opens the network connection editor. |
| Firewall state, ports/services, website blocks, and DNS mode | Firewall; system rules and block lists stay outside GitHub sync. |
| Bounded text/image clipboard history | Clipboard history; capture is opt-in. |
| Printer/scanner tools and optional dependencies | Printing & scanning. |
| Locale and timezone | Language & region. |

Default-app choices and explicit shortcut commands are separate settings. A
custom shortcut that names a specific app continues to launch that command.
For sound, select devices and per-app volumes in **Sound**; device state is
managed by PipeWire/WirePlumber and is not exported by GitHub sync.

### Saving and Hyprland appearance

Most bar, appearance, and locking preferences save automatically after a short
pause. Closing Settings flushes pending changes. Invalid values show an error
and leave the last saved configuration active; correct the value to resume
saving. System cleanup and keybinding edits have their own explicit save actions.

Preferences live in:

```text
~/.config/hyprshell/settings.json
```

The Windows page controls selected options such as gaps, borders,
rounding, opacity, blur, shadows, and animations. Empty or “Use config” values
leave that option controlled by your underlying Hyprland configuration.

Explicit overrides are written to `hyprshell/overrides.lua` for the supplied
Lua configuration. The settings backend also supports traditional `.conf`
main configurations. Changes are validated and backed up; a failed Hyprland
reload rolls back affected files.

Settings → Displays manages connected outputs and saves confirmed choices in
`hyprshell/displays.json` and generated `displays.lua`. New outputs follow the
automatic monitor rule. Arbitrary third-party Quickshell components and
Hyprland options outside the available settings still require editing the
appropriate configuration files. See
[the settings reference](docs/settings.md) for detailed behavior and extension
points.

### Editing shortcuts

Open **Settings → Keyboard shortcuts** to search active shortcuts and select
one to edit, or choose **+ New**. Record a key combination or enter it manually, add an
action description, and keep the existing action or supply a command. Click
**Save shortcut** to apply it. **Restore** resets an edited built-in shortcut;
**Remove** deletes an added shortcut.

The editor checks conflicts, validates the Hyprland configuration, and reloads
it. Failed validation or application restores the previous files. Saved edits
live in `~/.config/hyprshell/keybindings.json`; `keybindings.lua` is generated
from them and applied after the base Lua configuration. The `Super+K` overlay
shows active bindings, including these edits.

## Screen locking

The component default for automatic locking is disabled, but this checkout's
saved preferences enable Hyprlock after 10 idle minutes and before sleep.
Setup restores those saved preferences and installs Hyprlock and Hypridle in
the base manifest. To repair missing packages on an existing Arch installation:

```bash
sudo pacman -Syu --needed hypridle hyprlock
```

Open **Settings → Screen locking**, choose your locker command, and test it
with **Lock now**. Then enable automatic locking, choose an idle timeout, and
optionally enable locking before sleep. A timeout of 0 disables the idle timer.

Configure Hyprlock's appearance in `~/.config/hypr/hyprlock.conf`, or use your
chosen locker's own configuration. Custom commands support quoted arguments
and `~` paths; they do not expand environment variables or execute shell
operators. The locker must remain in the foreground until unlocked.

Hyprshell manages its own Hypridle child while automatic locking is enabled.
Disable a separately configured Hypridle service or autostart before enabling
this feature; Settings reports conflicts. Automatic locking runs with the
shell, so it depends on Hyprshell continuing to run. Closing the Settings
window does not stop it.

## System cleanup

Open **Settings → Cleanup** to configure cleanup of old thumbnail cache
files, eligible temporary files owned by your user, and old Hyprshell backups.

Choose Off, Daily, Weekly, or Monthly, select categories, and click **Save
cleanup settings**. Scheduling starts Off. The default age limit is 30 days,
and the newest five backup sets are retained.

Use **Preview scheduled cleanup rules…** to review eligible paths and sizes.
**Delete previewed files** confirms that specific cleanup. Scheduled runs use the saved rules
without prompting. Symlinks and active configurations are excluded, and
recently accessed or changed files are kept.

The schedule uses the systemd user timer `hyprshell-cleanup.timer`. Results are
recorded in `~/.local/state/hyprshell/cleanup-last.json` and the service journal.
The separate **Clean now · your files** controls let you analyze selected cache
and recovery-history categories, inspect individual files, exclude entries, and
confirm the preview. **System files · administrator access** provides separately
authenticated maintenance using each tool's retention policy. These manual
choices do not change automatic cleanup rules. Manual setup backups and
personal-file snapshots remain outside cleanup targets. See
[the settings reference](docs/settings.md) for category and preview behavior.

## Saving your setup to GitHub

The **Sync to GitHub** button in Settings snapshots your live desktop, commits locally, then pushes
to a repository named `hyprshell` in your authenticated GitHub account.

1. Open the sync popup and choose **Authenticate**.
2. Complete GitHub CLI browser sign-in in the Kitty terminal.
3. Use a fork of this project or create a repository named `hyprshell` in your
   account. For an empty standalone repository, leave README, license, and
   `.gitignore` initialization unchecked.
4. Select **Check again** and verify the displayed account and target.
5. Start the sync and check its result.

There is one canonical configuration under `config/`, including personal preferences.
When you choose Sync to GitHub, it captures live `hypr/` and `quickshell/` code, editable
Hyprland sections, and saved `hyprshell/settings.json`, cleanup preferences,
shortcut and display customizations, application appearance, default apps,
and login-startup choices.
It also captures installed copies of files already managed by the checkout:
portal preferences, autostart overrides, utilities, application shortcuts, and
the bundled `default.jpg` wallpaper. Other wallpapers stay local and are ignored
by Git. Additional personal files in those locations are
not imported automatically. It also commits project files: configuration,
utilities, assets, tools, tests, documentation, workflows, package manifests,
the installer, and README. This keeps the installation guide and installer in
sync with the desktop. Tracked deletions in these paths are included.

Boot and SDDM artwork, preferences, and their installers are preserved as
repository files. Sync does not read back root-owned boot or login files;
preserve changes to those themes in `config/boot/` or `config/sddm/` and their
installers before syncing. Setup derives the new machine's boot configuration
locally rather than copying the old machine's disk identifiers or boot images.

Backups, logs, Python caches, and the compiled spectrum helper are excluded
from the live snapshot. Files outside the explicit project paths remain
uncommitted. Review project and custom configuration content before syncing
to a public repository.

Manual desktop edits remain live and uncommitted until you choose **Sync to
GitHub**. Sync reconciles installed and checkout files, validates them, creates
a local commit for remaining changes, then pushes. Existing commits keep their
original subjects and bodies. A failed push leaves the local commit for retry.
Staged changes, unfinished merges, or conflicting repo/live copies require
resolution before publishing. Configure a Git commit identity on fresh clones.

**Sync from GitHub** checks the developer’s `orapagier/hyprshell` repository on
`main`, even when the checkout tracks your fork. The window identifies this source
and previews updates without committing local edits. Conflicts show both full-file
versions and a diff, with **Keep your local version** and **Use developer’s version**
checkboxes, including deletions. Select one version per conflict, click **Review choices**, acknowledge
the updated review, then **Sync now**. Local edits kept during an update remain
uncommitted until Sync to GitHub. Updates can add a merge commit for already
committed branch history, without including your unsynced edits. Pushes never
force or automatically merge remote changes. **Sync to GitHub** continues publishing
to your own repository; checking for developer updates leaves that destination intact.

Setup records the checkout location in
`~/.local/state/hyprshell/repository`. Re-running setup updates that pointer.

## Updating, backups, and restoring files

### Updating

Use **Sync from GitHub**, to the right of **Sync to GitHub** in Settings. Review
incoming commits, files, package requirements and compatibility findings. Once
blocking issues are resolved, acknowledge the hardware limitations and click
**Sync now**. The preview shows the exact source repository and branch.

**Keep my preferences** is the default, including when incoming preferences
changed without a Git conflict. Choose **Use developer preferences** for all
shown categories, or select individual categories. Kitty, mpv, and the default
wallpaper have separate choices. Use **Show comparison** to inspect differences;
after changing choices, click **Review choices** before syncing.

The update preserves selected preferences and original Git history, stages and
validates the candidate, and retains recovery files. Log out and back in after completion.
For an already updated local checkout, `./setup.sh --update` applies and validates
its desktop files without upgrading system packages. Use full setup when new
system dependencies or root-owned integration changes require it.

Fresh installations use the same committed configuration as this desktop.
Existing installations retain customized preferences. Fork the project to keep
your own taste and commits. See [updates, forks and recovery](docs/updates.md)
and the [fresh-install/hardware checklist](docs/acceptance.md).

### Backups and restoration

Deployment backups use `~/.local/state/hyprshell/backups/update-<timestamp>-<id>/`.
They contain changed files and a transaction journal, not whole configuration
directories or personal documents. Use the documented rollback command in
[updates.md](docs/updates.md#recovery); do not replace a complete configuration
directory with a partial deployment backup. Settings transactions retain their
own separate backup sets.

### Setup backups and personal files

**Settings → Backup & restore** creates dated Hyprshell setup backups covering
preferences, editable desktop Lua, displays, shortcuts, app integration, and
appearance. Select a backup to preview and restore it, then log out and back
in. A before-restore backup provides an undo path. These backups exclude installed shell code, system
packages, and personal documents. They are stored under
`~/.local/state/hyprshell/setup-backups/` and protected from cleanup.

The separate **Personal-file backups** controls copy selected folders to a local
destination, optionally on a schedule, and verify snapshot checksums. This is
off until configured. Snapshots, paths, and schedules stay local and do not go
to GitHub. Open the snapshot folder to recover files; snapshots are not deleted
automatically. Copy backups to another drive for protection against drive failure.

### Configuration and state paths

| Path | Purpose |
| --- | --- |
| `~/.config/hypr/` | Hyprland entry point, wallpaper scripts, and Hyprlock configuration. |
| `~/.config/quickshell/` | Installed shell components and helpers. |
| `~/.config/hyprshell/hyprland/` | Editable Lua sections for monitors, input, shortcuts, startup, and window rules. |
| `~/.config/hyprshell/settings.json` | Saved Hyprshell preferences. |
| `~/.config/hyprshell/displays.json` / `displays.lua` | Confirmed display choices and generated monitor rules. |
| `~/.config/hyprshell/cleanup.json` | Saved cleanup rules and schedule. |
| `~/.config/hyprshell/keybindings.json` / `keybindings.lua` | Saved shortcut edits and generated Lua bindings. |
| `~/.config/autostart/nm-applet.desktop` | Managed override hiding the duplicate network tray icon. |
| `~/.config/hyprshell/overrides.lua` | Generated Hyprland appearance overrides for Lua configs. |
| `~/.config/hyprshell/hypridle.conf` | Generated idle configuration when managed by Hyprshell. |
| `~/.config/xdg-desktop-portal/` | Desktop portal preferences. |
| `~/.local/bin/` | Installed launcher, session, and settings utilities. |
| `~/.local/state/hyprshell/` | Repository pointer, configuration backups, and cleanup results. |
| `~/.local/state/quickshell/bar.log` | Session launcher output. |
| `~/Pictures/Wallpapers/` | Wallpaper images. |

These are default paths. The installer and settings helpers respect
`XDG_CONFIG_HOME` and `XDG_STATE_HOME`; use the corresponding custom locations
if you set them. Wallpaper storage remains under `~/Pictures/Wallpapers`.

## Troubleshooting

Run desktop commands inside your Hyprland session so they can access its
Wayland socket, Hyprland socket, and user D-Bus session.

### The bar does not start

Check the launcher output and try starting it again:

```bash
tail -n 100 "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/bar.log"
~/.local/bin/start-quickshell-bar
```

Check that Quickshell is installed, the installed `quickshell/shell.qml` exists,
and the configured startup command points to `start-quickshell-bar`. From the
repository, check native dependencies with:

```bash
python3 tools/check_runtime.py --native
```

The launcher verifies both bar readiness and notification ownership and reports
startup failures in the log.

### Settings or the application launcher will not open

Both communicate with the running Hyprshell instance. The application launcher
tries to start the bar if it is unavailable; Settings requires the bar to be
running. If utilities or the desktop entry are missing, reinstall with
`./setup.sh --config-only`. Applications missing from the launcher may lack
an installed desktop entry.

### An Android phone does not appear in Files

Android USB file transfer uses `gvfs-mtp`. It is included in
the base desktop setup; older installations may have installed it only with
`--extra`. To add it to an existing Arch installation, run:

```bash
sudo pacman -Syu --needed gvfs-mtp
```

Unlock the phone, select **File transfer / Android Auto** in its USB options,
and accept any file-access prompt. After installation, close COSMIC Files,
reconnect the phone, and open it again (`Super+E`). Check its network/volume
locations for the phone. If it remains absent, log out and back in to refresh
the session's GVfs volume monitors.

In a desktop terminal, `gio mount -li` shows detected volumes. If the phone is
still absent, check that the cable supports data and try another USB port.
The phone's storage is accessed through MTP, so it does not need a disk mount
or an `/etc/fstab` entry.

### Notifications are missing

Ensure another notification daemon is not already holding
`org.freedesktop.Notifications` in your user session. Disable a conflicting
daemon's service or autostart, then restart Hyprshell. Check Settings →
Notifications for popup, Do Not Disturb, and per-app delivery choices, then check
the bell's inbox. You can send a test message with:

```bash
notify-send 'Hyprshell test' 'Check the notification inbox.'
```

### Audio, Wi-Fi, or Bluetooth controls are unavailable

Check their service status:

```bash
systemctl --user status pipewire pipewire-pulse wireplumber
systemctl status NetworkManager bluetooth
```

Also check hardware availability and radio state. No spectrum activity is
expected when the speaker output is silent. If compilation fails during
installation, check that GCC, libpulse, and FFTW are installed.

### Display, shortcuts, or icons do not look right

Review Settings → Displays and the keyboard layout described in the
first-login section; new outputs use the automatic monitor fallback. Change
shortcuts that invoke applications you do not use.
Missing glyphs usually indicate missing fonts; install the manifest's fonts
and restart the session. If bar groups overlap, reduce item widths or move
modules between groups.

### A settings change will not save

Read the error in Settings. Correct invalid values, check file permissions,
and resolve any concurrent edits before retrying. Malformed JSON must be
repaired before saving. Failed Hyprland reloads restore affected files; validate
your main configuration before trying the change again.

### GitHub sync fails

Check the displayed account, repository name, push permissions, and network
access. Re-authenticate if sign-in expired. Commit or unstage existing staged
changes, and finish any merge or rebase. If your remote branch has diverged,
resolve it through your normal Git workflow; the sync tool never force-pushes.

### Automatic locking does not work

Use **Lock now** to test the saved locker command first. Check that Hypridle
and the locker are installed, another Hypridle process is not conflicting,
and Hyprshell is running. Review errors on the Screen locking page.

## Project structure and references

For focused usage details, see [panel layout controls](docs/panel-layout-settings.md),
[Hyprdock](docs/hyprdock.md), [Hyprbar](docs/hyprbar.md),
[Show Desktop and recovery](docs/show-desktop.md), and
[settings, inheritance, and persistence](docs/settings.md).

| Location | Contents |
| --- | --- |
| `config/quickshell/` | QML/JavaScript shell, service bindings, and settings helpers. |
| `config/hypr/` | Bundled Hyprland configuration and wallpaper scripts. |
| `config/hyprshell/` | Saved preferences installed with the desktop. |
| `config/boot/` | Saved Plymouth preferences, animated Glass theme, source artwork, and static UKI splash. |
| `config/sddm/hyprshell-glass/` | Matching animated Qt 6 login theme and artwork. |
| `config/autostart/` | Managed application autostart overrides. |
| `config/xdg-desktop-portal/` | Portal configuration. |
| `bin/` | Shell launcher, application launcher, and settings shortcut. |
| `assets/` | Wallpapers and application desktop entries. |
| `tools/` | Installer and runtime validation helpers. |
| `docs/boot-splash.md` / `docs/login-appearance.md` | Boot/login installation, previews, portability limits, and recovery. |
| `tests/` | Python tests for installation, settings, sync, locking, and cleanup. |
| `config/quickshell/tests/` | QML component tests and spectrum checks. |
| `packages.txt` / `packages-apps.txt` | Base desktop and optional application manifests. |

For component details, see the [Quickshell guide](config/quickshell/README.md).
For settings validation, inheritance, persistence, and extension points, see
[the settings implementation reference](docs/settings.md).

Run the relevant checks from the repository root with dependencies installed:

```bash
python3 -m unittest discover -s tests -v
Hyprland --verify-config --config "$PWD/config/hypr/hyprland.lua"
cc -O2 config/quickshell/helpers/audio-spectrum.c \
  -o config/quickshell/helpers/audio-spectrum -lpulse-simple -lpulse -lfftw3 -lm
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input config/quickshell/tests
python3 config/quickshell/tests/test_spectrum.py
```

Python installer tests use isolated temporary home directories. QML tests cover
layout, menus, appearance, notifications, audio controls, and wallpaper sampling.
Spectrum tests check frequency separation and capture lifecycle. Full hardware
behavior still needs a real session with the relevant devices and services.

Bundled holiday rules may need updates for special government declarations.
Bundled wallpapers are third-party images; inclusion here does not grant new
ownership or licensing rights over them.

### Optional Hyprskill integration

[Hyprskill](docs/hyprskill.md) gives Codex, Claude Code, and OpenCode reusable
context about this desktop from any working directory. Open **Settings →
Hyprskill → Install Hyprskill**, or install its global links with
`python3 tools/install_hyprskill.py`. Restart your agents afterward; desktop
installation stays separate.
