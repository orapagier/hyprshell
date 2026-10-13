#!/usr/bin/env python3
"""Check installed daily-driver readiness; never expose device or network names."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def invoke(arguments):
    try:
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=5)
        if result.returncode and any(phrase in result.stderr.lower() for phrase in
                ('permission denied', 'operation not permitted', 'failed to connect to bus', 'access denied')):
            return None, ''
        return result.returncode, result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None, ''


def check(after_login=False, root=Path('/'), runner=invoke):
    rows = []

    def add(title, state, hint):
        rows.append(dict(title=title, state=state, hint=hint))

    for title, units in (
        ('Networking', ('NetworkManager.service',)),
        ('Bluetooth', ('bluetooth.service',)),
        ('Printing', ('cups.socket',)),
        ('Printer discovery', ('avahi-daemon.service',)),
        ('SSD maintenance', ('fstrim.timer',)),
        ('Time synchronization', ('chronyd.service', 'systemd-timesyncd.service', 'ntpd.service', 'ntp.service', 'openntpd.service')),
        ('Firewall', ('firewalld.service', 'ufw.service', 'nftables.service', 'iptables.service', 'ip6tables.service')),
    ):
        if title == 'SSD maintenance':
            from system_plan import environment
            discard = environment(root)['discard']
            if discard is not True:
                add(title, 'ok' if discard is False else 'unavailable',
                    'Discard is unsupported; existing trim policy preserved.' if discard is False else
                    'Discard capability unavailable; check storage from a normal system session.')
                continue
        states = [runner(['systemctl', 'is-active', unit])[0] for unit in units]
        add(title, 'ok' if 0 in states else 'unavailable' if None in states else 'attention',
            'Running.' if 0 in states else 'Check the service from a normal system session.')
    for title, units in (
        ('Audio services', ('pipewire.socket', 'pipewire-pulse.socket', 'wireplumber.service')),
    ):
        operation = 'is-active' if after_login else 'is-enabled'
        states = [runner(['systemctl', '--user', operation, unit])[0] for unit in units]
        add(title, 'ok' if all(code == 0 for code in states) else 'unavailable' if None in states else 'attention',
            'Running.' if after_login and all(code == 0 for code in states) else
            'Enabled for login.' if all(code == 0 for code in states) else 'Check user audio services after login.')
    commands = ('chromium', 'cosmic-files', 'kitty', 'mpv', 'mousepad', 'hyprlock',
                'hypridle', 'playerctl', 'gnome-keyring-daemon', 'simple-scan', 'system-config-printer')
    missing = [command for command in commands if not shutil.which(command)]
    if 'chromium' in missing and shutil.which('chromium-browser'):
        missing.remove('chromium')
    add('Everyday applications', 'attention' if missing else 'ok',
        'Missing: ' + ', '.join(missing) if missing else 'Installed.')
    drm = list((root / 'sys/class/drm').glob('card[0-9]*/device'))
    drivers = {os.path.basename(os.path.realpath(device / 'driver')) for device in drm if (device / 'driver').exists()}
    nvidia = any((device / 'vendor').is_file() and (device / 'vendor').read_text().strip() == '0x10de' for device in drm)
    add('Graphics driver', 'ok' if drivers else 'attention',
        'Kernel graphics driver detected; verify the Wayland session after reboot.' if drivers else
        'No DRM graphics driver detected. Install the driver for this GPU before starting Hyprland.')
    if nvidia:
        add('NVIDIA graphics', 'attention',
            'Verify the supported NVIDIA driver, DRM modesetting and Secure Boot module signing. See docs/daily-driver.md.')
    if after_login:
        for title, kind in (('Audio output', 'sinks'), ('Microphone input', 'sources')):
            code, value = runner(['pactl', '--format=json', 'list', kind])
            try:
                devices = json.loads(value) if code == 0 else None
                real = devices is not None and any('auto_null' not in device.get('name', '') and
                         not device.get('name', '').endswith('.monitor') for device in devices)
            except (ValueError, TypeError, AttributeError):
                devices, real = None, False
            add(title, 'ok' if real else 'unavailable' if devices is None else 'attention',
                'Device detected; test it in Sound settings.' if real else 'Check firmware and device selection in Sound settings.')
        code, interfaces = runner(['nmcli', '--terse', '--fields', 'TYPE', 'device'])
        add('Wi-Fi adapter', 'ok' if code == 0 and 'wifi' in interfaces.splitlines() else 'unavailable' if code != 0 else 'attention',
            'NetworkManager access unavailable; rerun from your desktop.' if code != 0 else
            'Adapter detected; select your network in Settings.' if 'wifi' in interfaces.splitlines() else
            'No Wi-Fi adapter detected; check firmware, drivers and hardware radio switches if Wi-Fi is required.')
        code, adapters = runner(['bluetoothctl', 'list'])
        add('Bluetooth adapter', 'ok' if code == 0 and adapters else 'unavailable' if code != 0 else 'attention',
            'Bluetooth access unavailable; rerun from your desktop.' if code != 0 else
            'Adapter detected; pair devices in Settings.' if adapters else 'No Bluetooth adapter detected; check firmware and hardware if required.')
        code, errors = runner(['hyprctl', 'configerrors'])
        add('Hyprland session', 'unavailable' if code != 0 else 'attention' if errors and errors.lower() != 'ok' else 'ok',
            'Review compositor errors in your desktop session.' if code != 0 or errors and errors.lower() != 'ok' else 'No configuration errors reported.')
    return {'version': 1, 'afterLogin': after_login, 'checks': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--after-login', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = check(args.after_login)
    for row in report['checks']:
        print(f"{row['state'].upper()}: {row['title']} — {row['hint']}")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('Reboot/login, then test lock/unlock, audio, suspend/resume, browser media, and screen sharing on this hardware.')
    # Observations from a TTY or sandbox cannot certify the next desktop login.
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
