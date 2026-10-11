#!/usr/bin/env python3
"""Install the saved SDDM appearance without restarting the login manager."""
import argparse
from pathlib import Path
import os
import re
import shlex
import subprocess

from install_boot_splash import REPO, UnsupportedBoot, apply_plan

THEME = 'hyprshell-glass'


def login_config(text):
    """Preserve authentication, autologin, display-server and unrelated settings."""
    values = {'Current': THEME, 'ThemeDir': '/usr/share/sddm/themes'}
    section = re.search(r'^\[Theme\][ \t]*(?:\n|\Z)(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if len(re.findall(r'^\[Theme\][ \t]*$', text, re.M)) > 1:
        raise UnsupportedBoot('Duplicate SDDM Theme sections need manual integration')
    if not section:
        prefix = text.rstrip() + '\n\n' if text.strip() else ''
        return prefix + '[Theme]\n' + ''.join(f'{key}={value}\n' for key, value in values.items())
    body = section[1]
    for key, value in values.items():
        matches = list(re.finditer(r'^[ \t]*' + key + r'[ \t]*=.*$', body, re.M))
        if len(matches) > 1:
            raise UnsupportedBoot(f'Duplicate SDDM {key} setting needs manual integration')
        if matches:
            match = matches[0]
            body = body[:match.start()] + key + '=' + value + body[match.end():]
        else:
            body = body.rstrip() + '\n' + key + '=' + value + '\n'
    return text[:section.start(1)] + body + text[section.end(1):]


def build_login_plan(root):
    manager = root / 'etc/systemd/system/display-manager.service'
    if manager.is_symlink() and Path(os.readlink(manager)).name != 'sddm.service':
        raise UnsupportedBoot('The configured login manager is not SDDM; leaving it unchanged')
    if not (root / 'usr/bin/sddm-greeter-qt6').is_file():
        raise UnsupportedBoot('Install the Qt 6 SDDM greeter first')
    source = REPO / 'config/sddm' / THEME
    files = [item for item in source.iterdir() if item.suffix in ('.qml', '.png', '.desktop')]
    required = {'Main.qml', 'metadata.desktop', 'GlassButton.qml', 'GlassCombo.qml',
                'background.png', 'card.png', 'title.png', 'title-glow.png', 'footer.png'}
    if not required.issubset({item.name for item in files}):
        raise UnsupportedBoot('Incomplete bundled SDDM theme; render its assets first')
    if any(not item.is_file() or item.is_symlink() for item in files):
        raise UnsupportedBoot('SDDM assets must be regular files')
    target = root / 'usr/share/sddm/themes' / THEME
    plan = {target / item.name: item.read_bytes() for item in files}
    config = root / 'etc/sddm.conf'
    plan[config] = login_config(config.read_text() if config.exists() else '')
    if any(path.is_symlink() or any(parent.is_symlink() for parent in path.parents
                                   if parent != root and root in parent.parents)
           for path in plan):
        raise UnsupportedBoot('Symlinked SDDM configuration needs manual integration')
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--with-boot-splash', action='store_true',
                        help='Install Plymouth and the matching UKI splash in the same transaction')
    args = parser.parse_args()
    try:
        plan = build_login_plan(Path('/'))
        commands, outputs = [], set()
        if Path('/etc/fedora-release').is_file():
            commands.append(['restorecon', '-RF', '/usr/share/sddm/themes/' + THEME, '/etc/sddm.conf'])
        if args.with_boot_splash:
            import json
            from install_boot_splash import build_plan
            if not any(Path(name).is_file() for name in ('/usr/lib/plymouth/script.so', '/usr/lib64/plymouth/script.so')):
                raise UnsupportedBoot('Install the Plymouth script plugin first')
            preference = json.loads((REPO / 'config/boot/plymouth.json').read_text())
            if Path('/etc/fedora-release').is_file():
                from install_boot_splash_fedora import build_plan as build_fedora_plan
                boot_plan, boot_commands, outputs = build_fedora_plan(Path('/'))
            else:
                boot_plan, boot_commands, outputs = build_plan(Path('/'), preference)
            # A login-only change must not force an otherwise unnecessary rebuild.
            if not any(not path.exists() or path.read_bytes() !=
                       (value.encode() if isinstance(value, str) else value)
                       for path, value in boot_plan.items()):
                boot_commands = []
                outputs = set()
            commands.extend(boot_commands)
            plan.update(boot_plan)
        for path, value in sorted(plan.items()):
            data = value.encode() if isinstance(value, str) else value
            print(('Unchanged: ' if path.exists() and path.read_bytes() == data else 'Update: ') + str(path))
        if args.dry_run:
            for command in commands:
                print('Would rebuild:', shlex.join(command))
            return
        if os.geteuid() != 0:
            parser.error('Run with sudo, or use --dry-run to preview')
        apply_plan(plan, commands, outputs, Path('/var/lib/hyprshell/appearance-backups'),
                   component='Startup appearance')
        print('SDDM will use Hyprshell Glass at the next login. No services were restarted.')
    except (UnsupportedBoot, OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Login appearance not configured: {exc}\nSee docs/login-appearance.md.\n')


if __name__ == '__main__':
    main()
