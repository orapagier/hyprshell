#!/usr/bin/env bash
# Install the native Hyprshell desktop on Arch Linux or Fedora Everything.
set -Eeuo pipefail
umask 022

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=install
DRY_RUN=0
INSTALL_APPS=0
SKIP_BOOT_SPLASH=0
SKIP_LOGIN_THEME=0
TIMEZONE=
DISTRO=auto
COPR=
COPR_SELECTED=0
UPDATE_ONLY=0

usage() {
  cat <<'HELP'
Usage: ./setup.sh [options]

Run as your normal user, with sudo access, on Arch Linux or Fedora Everything.
  --dry-run          Check installed packages and show the plan; change nothing
  --config-only      Update desktop files while preserving existing preferences
  --update           Update desktop files and validate them; no system upgrade
  --distro NAME      auto (default), arch, or fedora; cross-distro previews allowed
  --copr OWNER/REPO  Fedora desktop repository (default: lionheartp/Hyprland)
  --no-copr          Use only already enabled Fedora repositories
  --extra            Also install optional containers and terminal decoration
  --skip-boot-splash  Leave system boot configuration unchanged
  --skip-login-theme Leave the existing login screen appearance unchanged
  --timezone ZONE    Set the system timezone (default: preserve current timezone)
  --keep-timezone    Leave the system timezone unchanged
  -h, --help         Show this help

Hyprland and Quickshell are checked first; missing desktop dependencies are
installed through pacman or DNF. Fedora enables lionheartp/Hyprland unless
--no-copr is supplied. Everyday apps and firmware are included; no AUR apps are installed.
--config-only skips all package installation.
Existing configs are backed up under ~/.local/state/hyprshell/backups/.
XDG_CONFIG_HOME and XDG_STATE_HOME are respected. A reboot is recommended.
HELP
}

die() { printf 'hyprshell: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }
trap 'printf "hyprshell: setup failed at line %s. Fix the reported error and rerun setup.sh.\n" "$LINENO" >&2' ERR

while (( $# )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --config-only) MODE=config-only ;;
    --update) MODE=config-only; UPDATE_ONLY=1 ;;
    --distro|--copr)
      (( $# >= 2 )) || die "$1 requires a value"
      if [[ "$1" == --distro ]]; then DISTRO=$2; else COPR=$2; COPR_SELECTED=1; fi
      shift ;;
    --no-copr) COPR=; COPR_SELECTED=1 ;;
    --extra) INSTALL_APPS=1 ;;
    --skip-boot-splash) SKIP_BOOT_SPLASH=1 ;;
    --skip-login-theme) SKIP_LOGIN_THEME=1 ;;
    --keep-timezone) TIMEZONE= ;;
    --timezone)
      (( $# >= 2 )) || die '--timezone requires a timezone name'
      TIMEZONE=$2
      shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

[[ -n "${HOME:-}" && "$HOME" == /* ]] || die 'HOME must be an absolute path'
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}
[[ "$CONFIG_DIR" == /* && "$STATE_DIR" == /* ]] || die 'XDG paths must be absolute'
[[ -f "$REPO_DIR/config/quickshell/shell.qml" && -f "$REPO_DIR/packages.txt" ]] || die 'Run setup.sh from a complete clone of the repository'
# /etc/os-release is supplied by the operating system, never by the checkout.
OS_ID=
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  OS_ID=$(. /etc/os-release; printf '%s' "${ID:-}")
fi
if [[ "$DISTRO" == auto ]]; then DISTRO=$OS_ID; fi
[[ "$DISTRO" == arch || "$DISTRO" == fedora ]] || die 'Choose --distro arch or --distro fedora for a preview; installation supports Arch and Fedora'
if [[ "$DISTRO" == fedora && "$COPR_SELECTED" == 0 ]]; then COPR=lionheartp/Hyprland; fi
[[ -z "$COPR" || "$DISTRO" == fedora ]] || die '--copr is only supported on Fedora'
[[ -z "$COPR" || "$COPR" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die 'COPR must be OWNER/REPO'
PACKAGE_FILE=packages.txt
APP_PACKAGE_FILE=packages-apps.txt
if [[ "$DISTRO" == fedora ]]; then
  PACKAGE_FILE=packages-fedora.txt
  APP_PACKAGE_FILE=packages-apps-fedora.txt
fi
[[ -f "$REPO_DIR/$PACKAGE_FILE" ]] || die "Missing $PACKAGE_FILE"
mapfile -t PACKAGES < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$REPO_DIR/$PACKAGE_FILE")
if (( INSTALL_APPS )); then
  [[ -f "$REPO_DIR/$APP_PACKAGE_FILE" ]] || die "Missing $APP_PACKAGE_FILE"
  mapfile -t APP_PACKAGES < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$REPO_DIR/$APP_PACKAGE_FILE")
  for package in "${APP_PACKAGES[@]}"; do
    PACKAGES+=("$package")
  done
fi
# Optional lists may share packages (for example playerctl).
declare -A SEEN_PACKAGES=()
UNIQUE_PACKAGES=()
for package in "${PACKAGES[@]}"; do
  if [[ -z "${SEEN_PACKAGES[$package]:-}" ]]; then
    UNIQUE_PACKAGES+=("$package")
    SEEN_PACKAGES[$package]=1
  fi
done
PACKAGES=("${UNIQUE_PACKAGES[@]}")

login_manager() {
  local alias=/etc/systemd/system/display-manager.service
  if [[ -L "$alias" ]]; then
    [[ -e "$alias" ]] || die 'The display-manager.service alias is broken; repair it before running setup'
    basename "$(readlink "$alias")"
    return
  elif [[ -e "$alias" ]]; then
    printf '%s\n' display-manager.service
    return
  fi
  # Prefer an enabled manager, otherwise enable one already installed.
  local manager_units
  manager_units=$(systemctl list-unit-files --type=service --no-legend) || die 'Could not detect installed login managers; leaving the login screen unchanged'
  awk '
    $1 ~ /^(display-manager|sddm|gdm|lightdm|greetd|lxdm|ly|xdm|cosmic-greeter|entrance)\.service$/ {
      if (!first) first = $1
      if ($2 == "enabled") { print $1; found = 1; exit }
    }
    END { if (!found && first) print first }
  ' <<< "$manager_units"
}

LOGIN_UNIT=
if [[ "$MODE" == install ]]; then
  LOGIN_UNIT=$(login_manager)
  if [[ -z "$LOGIN_UNIT" ]]; then
    PACKAGES+=(sddm)
    if [[ "$DISTRO" == fedora ]]; then PACKAGES+=(sddm-x11); fi
  fi
fi

check_packages() {
  log 'Checking Hyprland and Quickshell'
  local package missing_text status
  if [[ "$DISTRO" == fedora ]]; then
    MISSING_PACKAGES=()
    for package in "${PACKAGES[@]}"; do
      if ! rpm -q --whatprovides "$package" >/dev/null 2>&1; then MISSING_PACKAGES+=("$package"); fi
    done
    printf 'Missing desktop packages: %s\n' "${MISSING_PACKAGES[*]:-none}"
    return
  fi
  for package in hyprland quickshell; do
    if pacman -T "$package" >/dev/null 2>&1; then
      printf '%s: installed (will be updated with the system)\n' "$package"
    else
      printf '%s: missing (will be installed)\n' "$package"
    fi
  done
  # -T understands providers such as hyprland-git, unlike pacman -Q hyprland.
  missing_text=$(pacman -T "${PACKAGES[@]}") || {
    status=$?
    (( status == 127 )) || die 'Could not query the pacman dependency database'
  }
  MISSING_PACKAGES=()
  if [[ -n "$missing_text" ]]; then
    mapfile -t MISSING_PACKAGES <<< "$missing_text"
  fi
  if ((${#MISSING_PACKAGES[@]})); then
    printf 'Missing desktop packages: %s\n' "${MISSING_PACKAGES[*]}"
  else
    printf 'All desktop packages are installed.\n'
  fi
}

if (( DRY_RUN )); then
  log 'Preview only; no files, packages, services, or settings will change'
  if [[ "$MODE" == install ]]; then
    if [[ "$DISTRO" == fedora ]]; then
      if command -v rpm >/dev/null; then check_packages; fi
      printf 'Full Fedora upgrade; ensure desktop packages: %s\n' "${PACKAGES[*]}"
      printf 'COPR: %s\n' "${COPR:-preserve enabled repositories}"
      printf 'Media: enable RPM Fusion free/nonfree; install Intel iHD and Freeworld H.264/HEVC codecs (targeted replacements)\n'
      printf 'Fonts: install bundled GoMono Nerd Font for shell icons\n'
    else
      if command -v pacman >/dev/null; then check_packages; fi
      printf 'Full Arch upgrade; ensure desktop packages: %s\n' "${PACKAGES[*]}"
    fi
    if [[ -n "$LOGIN_UNIT" ]]; then
      printf 'Login screen: preserve existing login manager; enable %s for graphical login\n' "$LOGIN_UNIT"
    else
      printf 'Login screen: install and enable SDDM (no login manager found)\n'
    fi
    if (( SKIP_LOGIN_THEME )); then
      printf 'Login appearance: leave the existing theme unchanged\n'
    else
      printf 'Login appearance: restore Hyprshell Glass when SDDM is the login manager\n'
    fi
    printf 'Enable NetworkManager, Bluetooth, UPower, PipeWire, and WirePlumber; Quickshell owns the notification inbox\n'
    printf 'Daily driver: enable printing/discovery and SSD trim; configure time sync and firewall while preserving configured alternatives\n'
    printf 'Firmware: general wireless/GPU/audio firmware, SOF, CPU microcode, and Mesa graphics; NVIDIA needs hardware-specific review\n'
    printf 'Timezone: %s\n' "${TIMEZONE:-unchanged}"
    if (( SKIP_BOOT_SPLASH )); then
      printf 'Boot splash: leave boot configuration unchanged\n'
    elif [[ "$DISTRO" == fedora ]]; then
      printf 'Boot splash: restore Hyprshell Glass using dracut; preserve Fedora kernel parameters\n'
    else
      printf 'Boot splash: restore saved Hyprshell Glass Plymouth theme for supported mkinitcpio boot layouts; preserve local disk/encryption options\n'
    fi
  fi
  printf 'Preferences: %s\n' "personal defaults for new users; preserve existing settings"
  printf 'Config destination: %s\nWallpaper destination: %s\n' "$CONFIG_DIR" "$HOME/Pictures/Wallpapers"
  printf 'Backups: %s/hyprshell/backups/\n' "$STATE_DIR"
  printf 'Bash shortcuts: pcm, fedora, ubuntu, and existing Distrobox names\n'
  exit 0
fi

(( EUID != 0 )) || die 'Run as your normal desktop user, not root or sudo ./setup.sh'
if [[ "$MODE" == install ]]; then
  [[ "$OS_ID" == "$DISTRO" ]] || die 'The selected distribution does not match this operating system'
  [[ ! -e /run/ostree-booted ]] || die 'Fedora Atomic/OSTree is not supported; use a traditional Fedora Everything installation'
  [[ $(uname -m) == x86_64 ]] || die 'This setup currently supports x86_64'
  if [[ "$DISTRO" == fedora ]]; then
    FEDORA_RELEASE=$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")
    python3 -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1]))["distributions"]["fedora"] else 1)' "$REPO_DIR/compatibility.json" "$FEDORA_RELEASE" || die 'Unsupported Fedora release; see compatibility.json before upgrading Fedora.'
  fi
  command -v sudo >/dev/null || die 'Install sudo and grant your user sudo access first'
  if [[ "$DISTRO" == fedora ]]; then
    command -v dnf >/dev/null || die 'DNF is required'
    command -v rpm >/dev/null || die 'RPM is required'
  else
    command -v pacman >/dev/null || die 'pacman is required'
  fi
  if [[ -n "$TIMEZONE" ]]; then
    [[ "$TIMEZONE" != /* && "$TIMEZONE" != *..* && -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Unknown timezone: $TIMEZONE"
  fi
  check_packages
  sudo -v
  if [[ "$DISTRO" == fedora ]]; then
    log 'Preparing RPM Fusion repositories for complete media support'
    bash "$REPO_DIR/tools/install_media_fedora.sh" --repositories-only
    if [[ -n "$COPR" ]]; then
      log "Enabling the Fedora desktop COPR: $COPR"
      sudo dnf install -y 'dnf5-command(copr)'
      sudo dnf copr enable -y "$COPR"
    fi
    log 'Checking that enabled Fedora repositories supply the complete package manifest'
    # Resolve the whole transaction before upgrading or replacing any configs.
    # DNF --assumeno returns 1 when a valid transaction is declined; use downloadonly
    # instead so resolver failures are unambiguous and no RPMs are installed here.
    sudo dnf install -y --setopt=install_weak_deps=False --downloadonly "${PACKAGES[@]}"
    log 'Upgrading Fedora and installing desktop dependencies'
    sudo dnf upgrade --refresh -y
    sudo dnf install -y --setopt=install_weak_deps=False "${PACKAGES[@]}"
    log 'Installing full media codecs and Intel hardware video acceleration'
    bash "$REPO_DIR/tools/install_media_fedora.sh" --install
  else
    log 'Upgrading Arch and installing missing desktop dependencies'
    # Always upgrade together with installation to avoid partial upgrades.
    sudo pacman -Syu --needed --noconfirm "${MISSING_PACKAGES[@]}"
  fi

  python3 - <<'PY'
import json, re, subprocess
info = json.loads(subprocess.check_output(['Hyprland', '--version-json'], text=True))
version = tuple(map(int, re.findall(r'\d+', info['version'])[:3]))
if version < (0, 56, 0):
    raise SystemExit('Hyprland 0.56 or newer is required; use compatible distribution packages (see docs/fedora.md on Fedora) and rerun.')
print('Hyprland version:', info['version'])
PY
  python3 "$REPO_DIR/config/quickshell/settings/compatibility.py" "$REPO_DIR/compatibility.json"
fi

command -v python3 >/dev/null || die 'Python 3 is required for --config-only'
# Reject an incompatible desktop before replacing configuration on config-only too.
if [[ "$MODE" == config-only && "$DISTRO" == fedora ]]; then
  python3 - <<'PY_VERSION'
import json, re, subprocess
info = json.loads(subprocess.check_output(['Hyprland', '--version-json'], text=True))
if tuple(map(int, re.findall(r'\d+', info['version'])[:3])) < (0, 56, 0):
    raise SystemExit('Hyprland 0.56+ is required before installing the Lua config; see docs/fedora.md.')
PY_VERSION
fi
# The bundled default.jpg is selected by hypr/wallpaper-start.sh.
[[ -f "$REPO_DIR/assets/wallpapers/default.jpg" ]] || die 'Missing bundled default wallpaper'
log 'Installing configs and wallpapers, with backups for changed files'
INSTALL_OPTIONS=()
if (( UPDATE_ONLY )); then
  python3 "$REPO_DIR/config/quickshell/settings/compatibility.py" "$REPO_DIR/compatibility.json"
  INSTALL_OPTIONS+=(--validate-native)
fi
python3 "$REPO_DIR/tools/install_configs.py" "$REPO_DIR" "${INSTALL_OPTIONS[@]}"
python3 "$REPO_DIR/tools/install_shell_shortcuts.py" "$REPO_DIR"

if [[ "$MODE" == config-only ]]; then
  log 'Configs installed. Packages, services, and timezone were left unchanged.'
  exit 0
fi

log 'Enabling networking, Bluetooth, battery information, and audio'
sudo systemctl enable --now NetworkManager.service bluetooth.service
# UPower is D-Bus activated (a static unit), so start it rather than enable it.
sudo systemctl start upower.service
if [[ "$DISTRO" == fedora ]]; then
  sudo systemctl enable --now tuned.service tuned-ppd.service
fi
if [[ -n "$TIMEZONE" ]]; then
  sudo timedatectl set-timezone "$TIMEZONE"
fi

# Enabling units works from a TTY even when there is no active user bus.
systemctl --user --root=/ --no-reload enable pipewire.socket pipewire-pulse.socket wireplumber.service
if systemctl --user daemon-reload; then
  systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service
else
  printf 'User services are enabled and will start at the next login.\n'
fi

if [[ -z "$LOGIN_UNIT" ]]; then LOGIN_UNIT=sddm.service; fi
log "Preparing graphical login with $LOGIN_UNIT"
sudo systemctl enable "$LOGIN_UNIT"
sudo systemctl set-default graphical.target

log 'Configuring printing, discovery, keyring login, time sync, firewall, and SSD maintenance'
sudo python3 "$REPO_DIR/tools/configure_daily_driver.py"

log 'Validating the installed configuration and refreshing fonts'
python3 "$REPO_DIR/tools/check_runtime.py" --native
# Distribution paths differ; never accidentally select a Qt 5 runner.
QML_TEST_RUNNER=$(python3 "$REPO_DIR/tools/check_runtime.py" --qmltestrunner)
QT_QPA_PLATFORMTHEME= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "$QML_TEST_RUNNER" -input "$CONFIG_DIR/quickshell/tests"
Hyprland --verify-config --config "$CONFIG_DIR/hypr/hyprland.lua"
fc-cache -f
xdg-user-dirs-update

if (( ! SKIP_LOGIN_THEME )); then
  # Never replace another display manager just to apply an SDDM theme.
  LOGIN_MANAGER=$(readlink /etc/systemd/system/display-manager.service || true)
  if [[ "${LOGIN_MANAGER##*/}" == sddm.service ]] ||
     [[ -z "$LOGIN_MANAGER" && ! -e /etc/systemd/system/display-manager.service && -x /usr/bin/sddm-greeter-qt6 ]]; then
    log 'Restoring the saved Hyprshell Glass SDDM login screen'
    sudo python3 "$REPO_DIR/tools/install_login_theme.py"
  else
    log 'Keeping the existing login manager appearance (not SDDM)'
  fi
fi

if (( ! SKIP_BOOT_SPLASH )); then
  log 'Restoring the saved Hyprshell Glass boot splash'
  SPLASH_INSTALLER=install_boot_splash.py
  if [[ "$DISTRO" == fedora ]]; then
    SPLASH_INSTALLER=install_boot_splash_fedora.py
  fi
  if sudo python3 "$REPO_DIR/tools/$SPLASH_INSTALLER"; then
    :
  else
    status=$?
    # Unsupported layouts are detected before writing. Rebuild/write failures
    # still stop setup so it cannot conceal a damaged boot image.
    (( status == 10 )) || die 'Boot splash failed; resolve the rebuild error before rebooting'
    printf 'Keeping the existing boot appearance on this unsupported layout.\n'
  fi
fi

log 'Checking installation readiness'
python3 "$REPO_DIR/tools/check_daily_driver.py" --output "$STATE_DIR/hyprshell/setup-readiness.json"
log 'Setup complete; review hardware checks after login'
printf 'Reboot, then select "Hyprland (uwsm-managed)" if you use a login screen.\n'
printf 'From a TTY run: uwsm start -e -D Hyprland hyprland.desktop\n'
printf 'SUPER+T opens Kitty; SUPER+E opens COSMIC Files; press and release SUPER for the launcher.\n'
printf 'Existing config backups: %s/hyprshell/backups/\n' "$STATE_DIR"
printf 'After login: python3 %q/tools/check_daily_driver.py --after-login\n' "$REPO_DIR"
