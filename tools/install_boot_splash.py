#!/usr/bin/env python3
"""Restore the saved Plymouth preference without copying machine boot settings."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


class UnsupportedBoot(ValueError):
    pass


def words(value):
    # Never evaluate shell expressions while editing root-owned configuration.
    if any(character in value for character in '$`\\;'):
        raise UnsupportedBoot('Dynamic shell configuration needs manual setup')
    return shlex.split(value, comments=True)


def add_parameters(value, parameters):
    """Keep disk/encryption options and replace only the saved parameter keys."""
    keys = {parameter.split('=', 1)[0] for parameter in parameters}
    current = shlex.split(value, posix=False)
    current = [parameter for parameter in current
               if parameter.split('=', 1)[0] not in keys]
    return ' '.join(current + parameters)


def add_hook(text):
    pattern = re.compile(r'^(\s*HOOKS\s*=\s*)\((.*?)\)', re.M | re.S)
    matches = list(pattern.finditer(text))
    assignments = re.findall(r'^\s*HOOKS\s*\+?=', text, re.M)
    if len(matches) != len(assignments):
        raise UnsupportedBoot('Non-literal HOOKS assignment needs manual setup')

    def replace(match):
        hooks = words(match[2])
        hooks = [hook for hook in hooks if hook != 'plymouth']
        anchor = 'systemd' if 'systemd' in hooks else 'udev'
        if anchor not in hooks:
            raise UnsupportedBoot('Plymouth requires the udev or systemd hook')
        hooks.insert(hooks.index(anchor) + 1, 'plymouth')
        return match[1] + '(' + ' '.join(hooks) + ')'

    return pattern.sub(replace, text), bool(matches)


def preset_values(text):
    """Accept ordinary mkinitcpio presets; leave custom shell logic untouched."""
    values = {}
    pattern = re.compile(r'^\s*(\w+)\s*=\s*(\([^)]*\)|[^\n]*)', re.M)
    remainder = pattern.sub('', text)
    if any(line.strip() and not line.lstrip().startswith('#')
           for line in remainder.splitlines()):
        raise UnsupportedBoot('Custom mkinitcpio preset logic needs manual setup')
    for match in pattern.finditer(text):
        name, value = match.groups()
        if value.startswith('('):
            values[name] = words(value[1:-1])
        else:
            parsed = words(value)
            if len(parsed) > 1:
                raise UnsupportedBoot(f'Non-literal preset value: {name}')
            values[name] = parsed[0] if parsed else ''
    return values


def theme_config(text, theme):
    section = re.search(r'^\[Daemon\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if not section:
        return '[Daemon]\nTheme=' + theme + '\n' + text
    body = section[1]
    if re.search(r'^\s*Theme\s*=', body, re.M):
        body = re.sub(r'^\s*Theme\s*=.*$', 'Theme=' + theme, body, flags=re.M)
    else:
        body = 'Theme=' + theme + '\n' + body
    return text[:section.start(1)] + body + text[section.end(1):]


def bundled_theme(root, theme):
    """Install shipped assets in the same backup/rebuild transaction as boot config."""
    source = REPO / 'config/boot' / theme
    if not source.is_dir():
        if not (root / f'usr/share/plymouth/themes/{theme}/{theme}.plymouth').is_file():
            raise UnsupportedBoot(f'Install Plymouth and its {theme} theme first')
        return {}
    files = [item for item in sorted(source.iterdir())
             if item.suffix in ('.plymouth', '.script', '.png')]
    required = {theme + '.plymouth', theme + '.script'}
    if not required.issubset({item.name for item in files}):
        raise UnsupportedBoot(f'Incomplete bundled theme: {theme}')
    if any(not item.is_file() or item.is_symlink() for item in files):
        raise UnsupportedBoot('Bundled theme must contain regular files')
    target = root / 'usr/share/plymouth/themes' / theme
    return {target / item.name: item.read_bytes() for item in files}


def uki_splash_options(text, values, active):
    """Replace the UKI's static logo while keeping other preset options intact."""
    uses_splash = False
    for name in active:
        if not values.get(name + '_uki', values.get(name + '_efi_image', '')):
            continue
        key = name + '_options'
        options = values.get(key, '')
        options = options if isinstance(options, list) else words(options)
        cleaned = []
        index = 0
        while index < len(options):
            option = options[index]
            if option == '--splash':
                if index + 1 >= len(options) or options[index + 1].startswith('-'):
                    raise UnsupportedBoot(f'Missing --splash argument in {key}')
                index += 2
            elif option.startswith('--splash='):
                index += 1
            else:
                cleaned.append(option)
                index += 1
        cleaned += ['--splash', '/usr/share/hyprshell/uki-splash.bmp']
        # Quote each option, then quote the whole shell string without evaluating it.
        line = key + '=' + shlex.quote(shlex.join(cleaned))
        matches = list(re.finditer(r'^[ \t]*' + key + r'[ \t]*=[ \t]*(\([^)]*\)|[^\n]*)', text, re.M))
        if len(matches) > 1:
            raise UnsupportedBoot(f'Duplicate preset option {key}')
        if matches:
            match = matches[0]
            text = text[:match.start()] + line + text[match.end():]
        else:
            text = text.rstrip() + '\n' + line + '\n'
        uses_splash = True
    return text, uses_splash


def build_plan(root, preference):
    """Inspect all targets before scheduling any write; root is injectable in tests."""
    def path(name):
        return root / name.lstrip('/')

    plan = {}
    hooks_found = False
    hook_paths = [path('/etc/mkinitcpio.conf')]
    hook_paths += sorted(path('/etc/mkinitcpio.conf.d').glob('*.conf'))
    for config in hook_paths:
        if not config.is_file():
            continue
        updated, found = add_hook(config.read_text())
        hooks_found |= found
        plan[config] = updated
    if not hooks_found:
        raise UnsupportedBoot('No supported mkinitcpio HOOKS configuration found')

    presets = list(path('/etc/mkinitcpio.d').glob('*.preset'))
    if not presets:
        raise UnsupportedBoot('No mkinitcpio presets found (dracut is not supported)')
    uki_cmdlines, kernels, images, outputs = set(), set(), set(), set()
    for preset in presets:
        preset_text = preset.read_text()
        values = preset_values(preset_text)
        active = values.get('PRESETS', [])
        if not isinstance(active, list):
            raise UnsupportedBoot(f'Expected a literal PRESETS array in {preset}')
        for name in active:
            config = values.get(name + '_config', values.get('ALL_config', ''))
            if config and config != '/etc/mkinitcpio.conf':
                raise UnsupportedBoot(f'Custom mkinitcpio config in {preset}')
            options = values.get(name + '_options', '')
            options = options if isinstance(options, list) else shlex.split(options)
            if any(option in ('--cmdline', '--no-cmdline', '--config', '-c')
                   or option.startswith(('--cmdline=', '--config=')) for option in options):
                raise UnsupportedBoot(f'Custom command-line/config options in {preset}')
            uki = values.get(name + '_uki', values.get(name + '_efi_image', ''))
            image = values.get(name + '_image', '')
            if not uki and not image:
                continue
            if any(not output.startswith('/') for output in (uki, image) if output):
                raise UnsupportedBoot(f'Expected absolute boot image paths in {preset}')
            outputs.update(path(output) for output in (uki, image) if output)
            kernel = values.get(name + '_kerneldest', values.get('ALL_kerneldest', ''))
            kernel = kernel or values.get(name + '_kver', values.get('ALL_kver', ''))
            if kernel:
                kernels.add(Path(kernel).name)
            if image:
                images.add(Path(image).name)
            if uki:
                cmdline = values.get(name + '_cmdline', values.get('ALL_cmdline', ''))
                if cmdline and not cmdline.startswith('/'):
                    raise UnsupportedBoot(f'Expected an absolute command-line path in {preset}')
                uki_cmdlines.add(path(cmdline or '/etc/kernel/cmdline'))
        if preference.get('uki_splash', False):
            updated, uses_splash = uki_splash_options(preset_text, values, active)
            if uses_splash:
                plan[preset] = updated
                splash = REPO / 'config/boot/uki-splash.bmp'
                if not splash.is_file() or splash.is_symlink():
                    raise UnsupportedBoot('Render the bundled UKI splash first')
                plan[path('/usr/share/hyprshell/uki-splash.bmp')] = splash.read_bytes()
    if not outputs:
        raise UnsupportedBoot('No active mkinitcpio image outputs found')

    parameters = preference['kernel_parameters']
    for cmdline in uki_cmdlines:
        if cmdline.is_dir():
            raise UnsupportedBoot('Custom UKI command-line directories need manual setup')
        # Default drop-ins can override the saved options; do not guess precedence.
        if cmdline == path('/etc/kernel/cmdline') and list(path('/etc/cmdline.d').glob('*.conf')):
            raise UnsupportedBoot('UKI command-line drop-ins need manual setup')
        if cmdline.is_file():
            value = ' '.join(line for line in cmdline.read_text().splitlines()
                             if line.strip() and not line.lstrip().startswith('#'))
        elif path('/usr/lib/kernel/cmdline').is_file():
            value = path('/usr/lib/kernel/cmdline').read_text().strip()
        else:
            value = path('/proc/cmdline').read_text().strip()
            # Bootloader bookkeeping is not a persistent kernel option.
            value = ' '.join(word for word in shlex.split(value, posix=False)
                             if not word.startswith(('BOOT_IMAGE=', 'initrd=')))
        if not value:
            raise UnsupportedBoot('Cannot determine this machine\'s UKI kernel parameters')
        plan[cmdline] = add_parameters(value, parameters) + '\n'

    grub = path('/etc/default/grub')
    grub_output = path('/boot/grub/grub.cfg')
    use_grub = grub.is_file() and grub_output.is_file()
    if use_grub:
        text = grub.read_text()
        matches = list(re.finditer(r'^\s*GRUB_CMDLINE_LINUX_DEFAULT\s*=(.*)$', text, re.M))
        if len(matches) != 1:
            raise UnsupportedBoot('GRUB requires one literal GRUB_CMDLINE_LINUX_DEFAULT')
        parsed = words(matches[0][1])
        if len(parsed) > 1:
            raise UnsupportedBoot('Custom GRUB command line needs manual setup')
        value = add_parameters(parsed[0] if parsed else '', parameters)
        replacement = 'GRUB_CMDLINE_LINUX_DEFAULT=' + shlex.quote(value)
        plan[grub] = text[:matches[0].start()] + replacement + text[matches[0].end():]

    entries_found = False
    for mount in ('/boot', '/efi', '/boot/efi'):
        for entry in path(mount + '/loader/entries').glob('*.conf'):
            text = entry.read_text()
            linux = re.search(r'^\s*linux\s+(\S+)', text, re.M | re.I)
            initrds = re.findall(r'^\s*initrd\s+(\S+)', text, re.M | re.I)
            # Only entries using this installation's mkinitcpio kernels/images.
            if not linux or Path(linux[1]).name not in kernels or not any(
                    Path(initrd).name in images for initrd in initrds):
                continue
            options = list(re.finditer(r'^\s*options[ \t]+([^\n]*)', text, re.M | re.I))
            if len(options) != 1:
                raise UnsupportedBoot(f'Expected one options line in {entry}')
            match = options[0]
            plan[entry] = (text[:match.start()] + 'options ' +
                           add_parameters(match[1], parameters) + text[match.end():])
            entries_found = True
    if not uki_cmdlines and not use_grub and not entries_found:
        raise UnsupportedBoot('Bootloader is not a supported UKI, GRUB, or systemd-boot layout')

    theme = path('/etc/plymouth/plymouthd.conf')
    plan[theme] = theme_config(theme.read_text() if theme.exists() else '', preference['theme'])
    plan.update(bundled_theme(root, preference['theme']))
    if any(target.is_symlink() or any(parent.is_symlink() for parent in target.parents
                                     if parent != root and root in parent.parents)
           for target in plan):
        raise UnsupportedBoot('Symlinked boot configuration needs manual setup')
    commands = [['mkinitcpio', '-P']]
    if use_grub:
        commands.append(['grub-mkconfig', '-o', str(grub_output)])
    return plan, commands, outputs


def write_atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.hyprshell-', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def apply_plan(plan, commands, outputs, backup_root, runner=subprocess.run, component='Boot splash'):
    data_plan = {path: value.encode() if isinstance(value, str) else value
                 for path, value in plan.items()}
    changed = {path: data for path, data in data_plan.items()
               if not path.exists() or path.read_bytes() != data}
    if not changed:
        print(f'{component} configuration is already current.')
        return
    for output in outputs:
        parent = output.parent
        while not parent.exists():
            parent = parent.parent
        if not os.access(parent, os.W_OK) or (output.exists() and not os.access(output, os.W_OK)):
            raise OSError(f'Boot image destination is not writable: {output}')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = backup_root / stamp
    originals = {}
    # Finish all backups before editing. Root/encryption parameters stay local.
    for path in changed:
        originals[path] = (path.read_bytes(), path.stat().st_mode & 0o777) if path.exists() else None
        if path.exists():
            saved = backup / str(path).lstrip('/')
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
    try:
        for path, data in changed.items():
            write_atomic(path, data, originals[path][1] if originals[path] else 0o644)
        for command in commands:
            runner(command, check=True)
    except Exception:
        for path, original in originals.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                write_atomic(path, *original)
        print(f'{component} configuration restored after failure.')
        if commands:
            print('Generated boot images may have changed; rerun the rebuild commands '
                  'successfully before rebooting: ' + '; '.join(shlex.join(command) for command in commands))
        raise
    print(f'{component} configured. Configuration backups: {backup}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    preference = json.loads((REPO / 'config/boot/plymouth.json').read_text())
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', preference['theme']):
        parser.error('Invalid Plymouth theme name')
    parameters = preference['kernel_parameters']
    if not isinstance(parameters, list) or not parameters or not all(
            isinstance(value, str) and re.fullmatch(r'[a-zA-Z0-9_.=-]+', value) for value in parameters):
        parser.error('Invalid kernel parameters')
    try:
        if not Path('/usr/lib/plymouth/script.so').is_file():
            raise UnsupportedBoot('Install the Plymouth script plugin first')
        plan, commands, outputs = build_plan(Path('/'), preference)
        for path, value in plan.items():
            data = value.encode() if isinstance(value, str) else value
            action = 'Unchanged' if path.exists() and path.read_bytes() == data else 'Update'
            print(f'{action}: {path}')
        if args.dry_run:
            for command in commands:
                print('Would rebuild:', shlex.join(command))
            return
        if os.geteuid() != 0:
            parser.error('Run with sudo, or use --dry-run to preview')
        apply_plan(plan, commands, outputs, Path('/var/lib/hyprshell/boot-backups'))
    except (UnsupportedBoot, OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Boot splash not configured: {exc}\nSee docs/boot-splash.md; '
                    'use setup.sh --skip-boot-splash to install only the desktop.\n')


if __name__ == '__main__':
    main()
