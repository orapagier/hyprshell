#!/usr/bin/env python3
"""Plan the entire desktop installation before any privileged changes."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import hardware_plan

# Every dependency gets a purpose in the preview. Core requirements are chosen
# by Hyprshell's runtime; hardware and existing policies choose optional backends.
GROUPS = {
    'Session and desktop': 'hyprland hyprland-guiutils hyprland-uwsm lua quickshell uwsm hyprpolkitagent xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk glib2 gsettings-desktop-schemas gtk3 qt6-declarative qt6-qtdeclarative qt6-qtdeclarative-devel qt6-svg qt6-qtsvg qt6-wayland qt6-qtwayland xorg-xwayland xorg-x11-server-Xwayland xorg-x11-xauth xorg-xhost xhost polkit dbus-broker dbus-broker-units',
    'Graphics, firmware and microcode': 'mesa mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers linux-firmware alsa-firmware kernel-modules kernel-modules-extra',
    'Networking': 'networkmanager NetworkManager NetworkManager-wifi nm-connection-editor nm-connection-editor-desktop wpa_supplicant dnsmasq curl',
    'Bluetooth': 'bluez bluez-utils',
    'Audio': 'pipewire pipewire-audio pipewire-alsa pipewire-pulse pipewire-pulseaudio wireplumber libpulse pulseaudio-utils pulseaudio-libs-devel fftw fftw-libs-double fftw-devel',
    'Power, battery and locking': 'upower brightnessctl hypridle hyprlock power-profiles-daemon tuned-ppd',
    'Appearance and fonts': 'awww fontconfig ttf-dejavu ttf-go-nerd noto-fonts noto-fonts-emoji pop-icon-theme adwaita-cursors dejavu-sans-fonts dejavu-sans-mono-fonts google-noto-sans-fonts google-noto-emoji-color-fonts adwaita-fonts-all adwaita-icon-theme',
    'Applications and file integration': 'kitty cosmic-files gvfs gvfs-mtp xdg-user-dirs flatpak xdg-utils loupe papers mpv mpv-mpris mousepad file-roller playerctl',
    'Media codecs and acceleration': 'ffmpeg ffmpeg-free libavcodec-freeworld libva-utils intel-media-driver libva-intel-driver mesa-va-drivers-freeworld',
    'Screenshots and clipboard': 'grim grimblast hyprland-contrib hyprpicker slurp swappy wl-clipboard cliphist libnotify',
    'Printing and scanning': 'cups system-config-printer simple-scan sane sane-backends avahi nss-mdns',
    'Credentials and system security': 'gnome-keyring gnome-keyring-pam seahorse firewalld',
    'Updates and administration': 'chrony pacman-contrib sudo git gh github-cli',
    'Backup and file transfer tools': 'rsync deja-dup restic rclone yt-dlp',
    'Boot and login appearance': 'sddm sddm-x11 plymouth plymouth-plugin-script dracut',
    'Archives and shell utilities': 'unzip zip 7zip man-db man-pages bash-completion htop zenity',
    'Build and system utilities': 'gcc rust cargo python python3 python-gobject python3-gobject sqlite util-linux procps-ng usbutils pciutils policycoreutils',
    'Optional extras': 'distrobox podman cmatrix',
}
CATEGORY = {package: title for title, packages in GROUPS.items() for package in packages.split()}
for package in hardware_plan.SELECTABLE:
    CATEGORY.setdefault(package, 'Graphics, firmware and microcode')


def invoke(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=10)
        denied = any(text in result.stderr.lower() for text in
                     ('operation not permitted', 'permission denied', 'failed to connect to bus', 'access denied'))
        if denied:
            return None, ''
        return result.returncode, result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None, ''


def installed_inventory(distro, packages, runner=invoke):
    if distro == 'fedora':
        code, text = runner(['rpm', '-qa', '--qf', '%{NAME}\n[%{PROVIDENAME}\n]'])
        if code != 0:
            return {p: 'unavailable' for p in packages}, set()
        providers = set(text.splitlines())
        return {p: 'installed' if p in providers else 'missing' for p in packages}, providers
    code, text = runner(['pacman', '-T', *packages])
    if code not in (0, 127):
        return {p: 'unavailable' for p in packages}, set()
    missing = set(text.splitlines()) if code == 127 else set()
    return {p: 'missing' if p in missing else 'installed' for p in packages}, set()


def environment(root=Path('/')):
    blocks = list((root / 'sys/class/block').glob('*'))
    discard = [hardware_plan.read(device / 'queue/discard_max_bytes') for device in blocks]
    readable = [value for value in discard if value.isdigit()]
    return {'discard': any(int(value) > 0 for value in readable) if readable else None,
            'bluetooth': bool(list((root / 'sys/class/bluetooth').glob('hci*'))),
            'backlight': bool(list((root / 'sys/class/backlight').glob('*'))),
            'memoryKnown': bool(hardware_plan.read(root / 'proc/meminfo'))}


def build(distro, base, login_unit='', skip_boot=False, skip_login=False,
          root=Path('/'), runner=invoke, hardware=None):
    hardware = hardware if hardware is not None else hardware_plan.detect(root)
    result = hardware_plan.plan(distro, hardware, base)
    result.update({'version': 2, 'services': {'enable': [], 'start': ['upower.service'], 'power': [],
                                           'trim': False, 'printing': True},
                   'blockers': [], 'subsystems': [], 'loginUnit': login_unit or 'sddm.service',
                   'bootAppearance': not skip_boot, 'loginAppearance': not skip_login,
                   'environment': environment(root)})
    states, providers = installed_inventory(distro, list(dict.fromkeys(result['packages'] + result['mediaPackages'])), runner)
    inventory_available = bool(states) and not all(state == 'unavailable' for state in states.values())
    cache = {}

    def package_present(package):
        if distro == 'fedora':
            return package in providers
        return runner(['pacman', '-Q', package])[0] == 0

    def configured(unit, user=False):
        key = (unit, user)
        if key not in cache:
            commands = ['systemctl'] + (['--user'] if user else [])
            results = [runner([*commands, action, unit])[0] for action in ('is-enabled', 'is-active')]
            cache[key] = True if 0 in results else None if None in results else False
        return cache[key]

    def remove(packages):
        result['packages'] = [p for p in result['packages'] if p not in packages]

    # Time/firewall policies are alternatives, not dependencies to replace.
    for package, units in (
        ('chrony', ('systemd-timesyncd.service', 'ntpd.service', 'ntp.service', 'openntpd.service')),
        ('firewalld', ('ufw.service', 'nftables.service', 'iptables.service', 'ip6tables.service')),
    ):
        if any(configured(unit) is True for unit in units):
            remove({package})
            result['notes'].append(f'{package}: preserve the configured alternative and its policies.')

    nm = configured('NetworkManager.service')
    network_alternatives = [unit for unit in ('systemd-networkd.service', 'connman.service', 'dhcpcd.service')
                            if configured(unit) is True]
    if network_alternatives and nm is not True:
        result['blockers'].append('Networking uses another configured manager (' + ', '.join(network_alternatives) + '). Hyprshell requires NetworkManager; review migration before full setup. No network service will be stopped automatically.')
    else:
        result['services']['enable'].append('NetworkManager.service')
    for unit in ('pulseaudio.service', 'pulseaudio.socket'):
        if configured(unit, user=True) is True:
            result['blockers'].append('Legacy PulseAudio is configured. Hyprshell requires PipeWire/WirePlumber; review migration before full setup instead of replacing a running audio server.')
            break
    if package_present('pulseaudio') and not any('PulseAudio' in b for b in result['blockers']):
        result['blockers'].append('Legacy PulseAudio is installed. Review the PipeWire migration before package resolution; setup will not erase the existing audio stack automatically.')

    # Preserve an existing provider, even on a desktop without a battery.
    power_units = [unit for unit in ('tuned-ppd.service', 'power-profiles-daemon.service', 'tlp-pd.service',
                                     'tuned.service', 'tlp.service', 'auto-cpufreq.service', 'system76-power.service')
                   if configured(unit) is True]
    if 'tuned-ppd.service' in power_units and 'tuned.service' in power_units:
        power_units.remove('tuned.service')  # One provider, two cooperating units.
    if 'tlp-pd.service' in power_units and 'tlp.service' in power_units:
        power_units.remove('tlp.service')
    power = power_units[0] if power_units else ''
    if len(power_units) > 1:
        result['notes'].append('Power: multiple existing providers detected; preserve them and review their compatibility.')
    if power:
        remove({'tuned-ppd', 'power-profiles-daemon'})
        result['notes'].append('Power: preserve ' + power + '; no competing daemon will be enabled.')
        result['powerProvider'] = power
    else:
        result['powerProvider'] = 'tuned-ppd.service' if distro == 'fedora' else 'power-profiles-daemon.service'
        result['services']['power'] = ['tuned.service', 'tuned-ppd.service'] if distro == 'fedora' else ['power-profiles-daemon.service']

    if result['environment']['bluetooth']:
        result['services']['enable'].append('bluetooth.service')
    else:
        result['notes'].append('Bluetooth: keep hotplug tools; no adapter detected, so do not start the daemon.')
    trim = result['environment']['discard']
    result['services']['trim'] = trim is True
    result['notes'].append('Storage: enable weekly fstrim for detected discard support.' if trim is True else
                           'Storage: keep the current trim policy; discard support is absent or unavailable.')
    if not result['environment']['backlight']:
        result['notes'].append('Brightness: keep hotplug tools; no controllable backlight detected.')
    if skip_boot:
        remove({'plymouth', 'plymouth-plugin-script'})
        result['notes'].append('Boot appearance: explicitly preserved; no Plymouth installation needed.')
    if login_unit and login_unit != 'sddm.service':
        result['loginAppearance'] = False
        result['notes'].append('Login: preserve ' + login_unit + ' and its appearance.')
    elif not login_unit:
        result['packages'] += ['sddm'] + (['sddm-x11'] if distro == 'fedora' else [])
    result['notes'].append('Printing/scanning: retain socket-activated tools for local, USB and network peripherals; vendor drivers require device-specific review.')
    result['notes'].append('Applications: use Hyprshell runtime dependencies and saved user preferences; keep existing desktops, associations and autostart settings during updates.')
    result['notes'].append('Backups/clipboard: install tools; retain existing opt-in capture and backup schedules.')
    result['notes'].append('Boot: preserve the bootloader, disk/encryption options and custom layouts; splash helper validates support before writing.')
    result['packages'] = list(dict.fromkeys(result['packages']))
    # New login-manager packages were added after the initial inventory read.
    if distro == 'fedora':
        for package in result['packages']:
            states.setdefault(package, 'installed' if package in providers else 'missing' if inventory_available else 'unavailable')
    else:
        new = [p for p in result['packages'] if p not in states]
        if new:
            added, _ = installed_inventory(distro, new, runner)
            states.update(added)
    if distro == 'fedora' and 'ffmpeg' in providers:
        remove({'ffmpeg-free'})
        result['notes'].append('Media: preserve installed full FFmpeg.')
    # Installed, disabled power packages can conflict at package resolution too.
    installed_power = next((package for package in ('tuned-ppd', 'power-profiles-daemon', 'tlp', 'auto-cpufreq', 'system76-power')
                            if (package in providers if distro == 'fedora' else states.get(package) == 'installed' or package_present(package))), '')
    if not power and installed_power:
        remove({'tuned-ppd', 'power-profiles-daemon'})
        result['services']['power'] = []
        result['powerProvider'] = installed_power
        result['notes'].append('Power: preserve installed ' + installed_power + ' and its existing service state; no competing package or daemon added.')
    elif not power:
        result['notes'].append('Power: no existing provider detected; select ' + result['powerProvider'] + '.')
    result['packageStates'] = {p: states[p] for p in list(dict.fromkeys(result['packages'] + result['mediaPackages']))}
    result['packageInventoryAvailable'] = inventory_available
    if all(state == 'unavailable' for state in result['packageStates'].values()):
        result['notes'].append('Installed package inventory unavailable; full setup will require a working package database.')
    for title in GROUPS:
        packages = [p for p in result['packageStates'] if CATEGORY.get(p, 'Build and system utilities') == title]
        if packages:
            result['subsystems'].append({'title': title, 'packages': packages,
                                        'installed': sum(result['packageStates'][p] == 'installed' for p in packages),
                                        'missing': [p for p in packages if result['packageStates'][p] == 'missing'],
                                        'unavailable': sum(result['packageStates'][p] == 'unavailable' for p in packages)})
    if any(value is None for (unit, user), value in cache.items() if not user):
        result['notes'].append('System service state unavailable in this session; service policies must be rechecked before privileged setup.')
    if any(value is None for (unit, user), value in cache.items() if user):
        result['notes'].append('User audio service state unavailable: installed audio packages are checked; user services can be enabled for the next login from a TTY.')
    result['serviceStateAvailable'] = all(value is not None for (unit, user), value in cache.items() if not user)
    return result


def render(result, form):
    if form == 'safety':
        print('System preflight: package database and service policies checked; no conflicting backend migration planned.')
    elif form in ('packages', 'media', 'enable', 'start', 'power'):
        values = result['packages'] if form == 'packages' else result['mediaPackages'] if form == 'media' else result['services'][form]
        print('\n'.join(values))
    elif form == 'summary':
        print('System plan: ' + result['distribution'] + '; CPU ' + (', '.join(result['cpuVendors']) or 'unknown') +
              '; GPU vendors ' + (', '.join(result['gpuVendors']) or 'unknown'))
        print('  Planned services: ' + ', '.join(result['services']['enable'] + result['services']['start'] + result['services']['power']))
        for group in result['subsystems']:
            print(f"  {group['title']}: {group['installed']} installed; {len(group['missing'])} missing; {group['unavailable']} unavailable")
            if group['missing']:
                print('    Install: ' + ', '.join(group['missing']))
        for note in result['notes']:
            print('Decision: ' + note)
        for blocker in result['blockers']:
            print('BLOCKED: ' + blocker)
    else:
        json.dump(result, sys.stdout, indent=2); print()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--distro', choices=('arch', 'fedora'))
    parser.add_argument('--manifest', type=Path, action='append', default=[])
    parser.add_argument('--login-unit', default='')
    parser.add_argument('--skip-boot', action='store_true')
    parser.add_argument('--skip-login', action='store_true')
    parser.add_argument('--read-plan', action='store_true')
    parser.add_argument('--format', choices=('json', 'packages', 'media', 'summary', 'enable', 'start', 'power', 'safety'), default='json')
    parser.add_argument('--require-safe', action='store_true')
    args = parser.parse_args()
    if args.read_plan:
        result = json.load(sys.stdin)
    else:
        if not args.distro:
            parser.error('--distro is required to build a plan')
        result = build(args.distro, [p for path in args.manifest for p in hardware_plan.manifest(path)],
                       args.login_unit, args.skip_boot, args.skip_login)
    if args.require_safe and (result['blockers'] or not result['serviceStateAvailable'] or not result['packageInventoryAvailable']):
        render(result, 'summary')
        raise SystemExit('Resolve the reported conflicts or run full setup from a normal system session before any privileged changes.')
    render(result, args.format)


if __name__ == '__main__':
    main()
