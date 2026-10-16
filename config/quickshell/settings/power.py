#!/usr/bin/env python3
"""Session power helpers; fixed argv, bounded commands, no privileged config writes."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import system_packages


def state_root():
    return Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'hyprshell'


@contextmanager
def power_lock():
    root = state_root()
    root.mkdir(parents=True, exist_ok=True)
    with (root / 'power.lock').open('w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield root


def command(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
    except FileNotFoundError:
        package = {'powerprofilesctl': 'power-profiles-daemon', 'hyprctl': 'hyprland'}.get(argv[0], argv[0])
        raise ValueError(f'Install {package} to use this control') from None
    except subprocess.TimeoutExpired:
        raise ValueError(f'{argv[0]} did not respond in time') from None
    if result.returncode:
        detail = (result.stderr or result.stdout).strip().splitlines()
        raise ValueError((detail[0][:300] if detail else f'{argv[0]} failed'))
    return result.stdout


def backlight():
    text = command(['brightnessctl', '--class=backlight', '--machine-readable'])
    for line in text.splitlines():
        parts = line.split(',')
        if len(parts) == 5 and parts[1] == 'backlight':
            name, _, current, _, maximum = parts
            if not re.fullmatch(r'[A-Za-z0-9_.:-]+', name):
                continue
            current, maximum = int(current), int(maximum)
            if maximum > 0 and 0 <= current <= maximum:
                return {'device': name, 'raw': current, 'max': maximum,
                        'percent': round(current * 100 / maximum)}
    raise ValueError('No controllable screen backlight found. External monitors may require their own controls.')


def set_raw(device, value):
    command(['brightnessctl', '--class=backlight', '--device=' + device, 'set', str(value)])


def set_brightness(percent):
    if type(percent) is not int or not 1 <= percent <= 100:
        raise ValueError('Brightness must be a whole percentage from 1 to 100')
    with power_lock() as root:
        info = backlight()
        set_raw(info['device'], max(1, round(info['max'] * percent / 100)))
        # A manual change becomes the new brightness; resume must not undo it.
        (root / 'power-brightness.json').unlink(missing_ok=True)
    return backlight()


def dim():
    from backend import read_power, effective_power, atomic
    with power_lock() as root:
        saved = root / 'power-brightness.json'
        if saved.exists():
            return
        info = backlight()
        target = max(1, round(info['max'] * effective_power(read_power(), os.environ.get('HYPRSHELL_IDLE_BATTERY') == '1')['dimPercent'] / 100))
        if info['raw'] <= target:
            return
        # Save before changing brightness so a failure never loses the original.
        atomic(saved, json.dumps(dict(info, dimmed=target)))
        set_raw(info['device'], target)


def restore():
    with power_lock() as root:
        saved = root / 'power-brightness.json'
        if not saved.exists():
            return
        info = backlight()
        data = json.loads(saved.read_text())
        if info['device'] == data['device'] and info['max'] == data.get('max') and info['raw'] == data['dimmed']:
            set_raw(info['device'], data['raw'])
        saved.unlink()


def dpms(enabled):
    from backend import atomic
    with power_lock() as root:
        marker = root / 'power-screen-off'
        if enabled and not marker.exists():
            return
        action = 'enable' if enabled else 'disable'
        command(['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "' + action + '" })'])
        if enabled:
            marker.unlink(missing_ok=True)
        else:
            atomic(marker, 'off\n')


def resume():
    from backend import recover_locker
    # Attempt display restoration and lock recovery independently.
    errors = []
    for action in (lambda: dpms(True), restore, recover_locker):
        try:
            action()
        except Exception as error:
            errors.append(str(error))
    if errors:
        raise ValueError('; '.join(errors))


def power_profile_property(name, value=None):
    """Use Fedora tuned-ppd's compatible API without a second power daemon."""
    from gi.repository import Gio, GLib
    interface = 'net.hadess.PowerProfiles'
    try:
        connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        arguments = GLib.Variant('(ss)', (interface, name)) if value is None else GLib.Variant(
            '(ssv)', (interface, name, GLib.Variant('s', value)))
        result = connection.call_sync(interface, '/net/hadess/PowerProfiles',
                                      'org.freedesktop.DBus.Properties',
                                      'Get' if value is None else 'Set', arguments,
                                      None, Gio.DBusCallFlags.NONE, 5000, None)
        return result.unpack()[0] if value is None else None
    except GLib.Error as error:
        raise ValueError('Power profiles unavailable. Check tuned-ppd and the authorization agent: ' + str(error)) from None


def profiles():
    if system_packages.distribution() == 'fedora':
        rows = power_profile_property('Profiles')
        available = [row['Profile'] for row in rows
                     if row.get('Profile') in ('power-saver', 'balanced', 'performance')]
        active = power_profile_property('ActiveProfile')
        if active not in available:
            raise ValueError('Power profile service did not report a supported current profile')
        return {'available': available, 'active': active}
    try:
        text = command(['powerprofilesctl', 'list'])
    except ValueError as error:
        raise ValueError('Power profiles unavailable. Check power-profiles-daemon: ' + str(error)) from None
    available = re.findall(r'^\s*\*?\s*(power-saver|balanced|performance):\s*$', text, re.M)
    active = command(['powerprofilesctl', 'get']).strip()
    if active not in available:
        raise ValueError('Power profile service did not report a supported current profile')
    return {'available': available, 'active': active}


def apply_profile():
    from backend import read_power
    profile = read_power()['profile']
    if profile == 'system':
        return
    info = profiles()
    if profile not in info['available']:
        raise ValueError(f'{profile} is not supported on this machine. Choose another profile or Use system setting.')
    if profile != info['active']:
        if system_packages.distribution() == 'fedora':
            power_profile_property('ActiveProfile', profile)
        else:
            command(['powerprofilesctl', 'set', profile])


def lid_state():
    paths = sorted(Path('/proc/acpi/button/lid').glob('*/state'))
    if not paths:
        raise ValueError('No readable laptop lid sensor was found. Use system lid behavior on this hardware.')
    states = [path.read_text().strip().split()[-1] for path in paths]
    if any(state not in ('open', 'closed') for state in states):
        raise ValueError('Laptop lid sensor reported an unknown state')
    return all(state == 'closed' for state in states)


def watch_lid():
    from backend import read_power
    action = read_power()['lidAction']
    previous = lid_state()
    while True:
        time.sleep(1)
        closed = lid_state()
        # Never suspend just because the shell starts with its lid closed.
        if closed and not previous and action == 'suspend':
            command(['systemctl', 'suspend'])
        previous = closed


def run_lid():
    from backend import read_power
    if read_power()['lidAction'] == 'system':
        return
    lid_state()  # Fail before inhibiting system handling on unsupported hardware.
    os.execvp('systemd-inhibit', ['systemd-inhibit', '--what=handle-lid-switch',
              '--who=Hyprshell', '--why=Session lid preference', '--mode=block',
              '--no-ask-password', sys.executable, str(Path(__file__).resolve()), '--watch-lid'])


def status():
    result = {'ok': True, 'brightness': None, 'profiles': None, 'lidSupported': False}
    for key, getter in (('brightness', backlight), ('profiles', profiles)):
        try:
            result[key] = getter()
        except Exception as error:
            result[key + 'Error'] = str(error)
    try:
        lid_state()
        result['lidSupported'] = True
    except Exception as error:
        result['lidError'] = str(error)
    return result


def main():
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    for flag in ('status', 'dim', 'restore', 'screen-off', 'resume', 'apply-profile', 'lid', 'watch-lid'):
        actions.add_argument('--' + flag, action='store_true')
    actions.add_argument('--brightness', type=int)
    args = parser.parse_args()
    try:
        if args.status:
            result = status()
        elif args.brightness is not None:
            result = {'ok': True, 'brightness': set_brightness(args.brightness)}
        else:
            action = next(flag for flag in ('dim', 'restore', 'screen_off', 'resume', 'apply_profile', 'lid', 'watch_lid') if getattr(args, flag))
            if action == 'screen_off':
                dpms(False)
            else:
                globals()[{'lid': 'run_lid'}.get(action, action)]()
            result = {'ok': True}
    except Exception as error:
        if args.lid or args.watch_lid:
            print(str(error), file=sys.stderr)
        else:
            print(json.dumps({'ok': False, 'message': str(error)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
