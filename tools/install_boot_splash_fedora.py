#!/usr/bin/env python3
"""Install Hyprshell Glass on Fedora's ordinary dracut/BLS boot layout."""
import argparse
from pathlib import Path
import os
import shlex
import subprocess

from install_boot_splash import (UnsupportedBoot, apply_plan, bundled_theme,
                                 theme_config)


def build_plan(root):
    def path(name):
        return root / name.lstrip('/')

    if not path('/etc/fedora-release').is_file() or path('/run/ostree-booted').exists():
        raise UnsupportedBoot('Use a traditional Fedora installation')
    if not path('/usr/lib64/plymouth/script.so').is_file() and not path('/usr/lib/plymouth/script.so').is_file():
        raise UnsupportedBoot('Install plymouth-plugin-script first')
    kernels = list(path('/boot').glob('vmlinuz-*'))
    outputs = {path('/boot') / ('initramfs-' + kernel.name.removeprefix('vmlinuz-') + '.img')
               for kernel in kernels if 'rescue' not in kernel.name}
    if not outputs or not all(image.is_file() for image in outputs):
        raise UnsupportedBoot('No ordinary Fedora kernel/initramfs pairs found; custom UKI layouts need manual integration')
    if not list(path('/boot/loader/entries').glob('*.conf')):
        raise UnsupportedBoot('Expected Fedora BLS boot entries; custom bootloaders need manual integration')
    theme = path('/etc/plymouth/plymouthd.conf')
    plan = bundled_theme(root, 'hyprshell')
    plan[theme] = theme_config(theme.read_text() if theme.exists() else '', 'hyprshell')
    plan[path('/etc/dracut.conf.d/90-hyprshell-plymouth.conf')] = 'add_dracutmodules+=" plymouth "\n'
    if any(target.is_symlink() or any(parent.is_symlink() for parent in target.parents
                                     if parent != root and root in parent.parents)
           for target in plan):
        raise UnsupportedBoot('Symlinked boot configuration needs manual integration')
    labels = [str(path('/usr/share/plymouth/themes/hyprshell')), str(theme),
              str(path('/etc/dracut.conf.d/90-hyprshell-plymouth.conf'))]
    return plan, [['restorecon', '-RF', *labels], ['dracut', '--regenerate-all', '--force']], outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        plan, commands, outputs = build_plan(Path('/'))
        for path in plan:
            print('Manage:', path)
        if args.dry_run:
            for command in commands:
                print('Would rebuild:', shlex.join(command))
            return
        if os.geteuid() != 0:
            parser.error('Run with sudo, or use --dry-run to preview')
        apply_plan(plan, commands, outputs, Path('/var/lib/hyprshell/boot-backups'),
                   component='Fedora boot splash')
        print('Kernel parameters preserved. Plymouth graphics require rhgb; see docs/fedora.md.')
    except (UnsupportedBoot, OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Fedora boot splash not configured: {exc}\n'
                    'See docs/fedora.md; use --skip-boot-splash for custom boot layouts.\n')


if __name__ == '__main__':
    main()
