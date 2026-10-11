"""Explicit optional-tool installation, with normal terminal authentication."""
import shutil
import subprocess

PACKAGES = {
    'clipboard': ['cliphist', 'wl-clipboard', 'xdg-utils'],
    'printing': ['cups', 'system-config-printer', 'sane', 'simple-scan'],
}


def install(group):
    if group not in PACKAGES:
        raise ValueError('Unknown optional tool group.')
    if not shutil.which('kitty'):
        raise ValueError('Kitty is required to open the installation terminal.')
    result = subprocess.run(['kitty', '--detach', '--hold', '--title', 'Hyprshell optional tools',
                             'sudo', 'pacman', '-Syu', '--needed', *PACKAGES[group]],
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError('Could not open the installation terminal. Try from the desktop session.')
    return {'ok': True, 'message': 'Review the full system upgrade and optional packages in the terminal. Refresh here after installation.'}
