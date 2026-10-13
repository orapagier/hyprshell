#!/usr/bin/env python3
"""Check native Hyprshell desktop commands."""
import ctypes
from ctypes.util import find_library
from pathlib import Path
import shutil
import sys


def qmltestrunner():
    for name in ('/usr/lib/qt6/bin/qmltestrunner', '/usr/lib64/qt6/bin/qmltestrunner',
                 '/usr/lib64/qt6/libexec/qmltestrunner', '/usr/lib/qt6/libexec/qmltestrunner'):
        if Path(name).is_file():
            return name
    if shutil.which('qmltestrunner-qt6'):
        return shutil.which('qmltestrunner-qt6')
    raise SystemExit('Missing Qt 6 qmltestrunner (Arch: qt6-declarative; Fedora: qt6-qtdeclarative-devel)')


def check_native():
    required = ('luac', 'Hyprland', 'hyprctl', 'awww', 'awww-daemon', 'nmcli', 'nm-connection-editor',
                'bluetoothctl', 'pactl', 'paplay', 'wpctl', 'kitty', 'cosmic-files', 'uwsm',
                'sqlite3', 'cc', 'busctl', 'systemctl', 'brightnessctl',
                'hypridle', 'hyprlock', 'mpv', 'playerctl', 'mousepad', 'gnome-keyring-daemon',
                'system-config-printer', 'simple-scan', 'systemd-inhibit',
                'grim', 'slurp', 'swappy', 'fc-cache', 'xdg-user-dirs-update',
                'sudo')
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config/quickshell/settings'))
    from system_packages import distribution
    # Power management can belong to an existing PPD/TLP/tuned policy. Its
    # optional Settings controls already report unavailable providers gracefully.
    required += ('dnf', 'rpm') if distribution() == 'fedora' else ('pacman', 'checkupdates')
    missing = [name for name in required if not shutil.which(name)]
    if not (shutil.which('quickshell') or shutil.which('qs')):
        missing.append('quickshell')
    qmltestrunner()
    if missing:
        raise SystemExit('Missing desktop commands: ' + ', '.join(missing))
    ctypes.CDLL(find_library('pulse-simple') or 'libpulse-simple.so.0')
    ctypes.CDLL(find_library('fftw3') or 'libfftw3.so.3')
    from gi.repository import Gio
    Gio.AppInfo.get_all()  # Require Python's GIO bindings used by application Settings.
    print('Native Hyprshell commands, Qt 6, PulseAudio client library, and FFTW: OK')


if __name__ == '__main__':
    if '--qmltestrunner' in sys.argv:
        print(qmltestrunner())
    else:
        check_native()
