#!/usr/bin/env python3
"""Install only the public config payload; preserve replaced paths in backups."""
from datetime import datetime
import filecmp
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def same(source, destination):
    if destination.is_symlink() or not destination.exists():
        return False
    if source.is_file():
        return destination.is_file() and filecmp.cmp(source, destination, shallow=False)
    if not destination.is_dir():
        return False
    comparison = filecmp.dircmp(source, destination, ignore=['__pycache__'])
    if comparison.left_only or comparison.right_only or comparison.common_funny:
        return False
    return all(same(source / name, destination / name)
               for name in comparison.common_files + comparison.common_dirs)


def install(repo):
    # Validate and regenerate portable overrides before replacing live files.
    spec = importlib.util.spec_from_file_location('hyprshell_settings', repo / 'config/quickshell/settings/backend.py')
    settings_backend = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(settings_backend)
    saved_settings = settings_backend.validate(json.loads((repo / 'config/hyprshell/settings.json').read_text()))
    sys.path.insert(0, str(repo / 'config/quickshell/settings'))
    from behavior import validate as validate_behavior, render as render_behavior
    behavior_path = repo / 'config/hyprshell/behavior.json'
    behavior_source = render_behavior(validate_behavior(json.loads(behavior_path.read_text()))) if behavior_path.exists() else None
    overrides = settings_backend.render_hypr(saved_settings['hyprland'], True, saved_settings['accessibility'])
    home = Path(os.environ['HOME'])
    config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + str(time.time_ns())
    backup = state / 'hyprshell/backups' / stamp

    def put(source, destination, relative):
        if same(source, destination):
            print('Unchanged:', destination)
            return
        destination.parent.mkdir(parents=True, exist_ok=True)
        saved = backup / relative
        with tempfile.TemporaryDirectory(prefix='.hyprshell-stage-', dir=destination.parent) as temporary:
            staged = Path(temporary) / 'payload'
            if source.is_dir():
                shutil.copytree(source, staged, ignore=shutil.ignore_patterns('__pycache__'))
            else:
                shutil.copy2(source, staged)
            existed = os.path.lexists(destination)
            if existed:
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(destination), str(saved))
                print('Backed up:', saved)
            try:
                os.replace(staged, destination)
            except OSError:
                if existed:
                    shutil.move(str(saved), str(destination))
                raise
        print('Installed:', destination)

    for name in ('hypr', 'xdg-desktop-portal'):
        put(repo / 'config' / name, config / name, Path('config') / name)

    put(repo / 'config/xdg-terminals.list', config / 'xdg-terminals.list', Path('config/xdg-terminals.list'))

    # Install only managed entries; keep other applications' autostart files.
    for desktop in sorted((repo / 'config/autostart').glob('*.desktop')):
        put(desktop, config / 'autostart' / desktop.name,
            Path('config/autostart') / desktop.name)

    # Compile before replacing the destination, so a failed build leaves it intact.
    with tempfile.TemporaryDirectory(prefix='hyprshell-quickshell-') as temporary:
        payload = Path(temporary) / 'quickshell'
        shutil.copytree(repo / 'config/quickshell', payload,
                        ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
        subprocess.run(['cc', '-O2', str(payload / 'helpers/audio-spectrum.c'),
                        '-o', str(payload / 'helpers/audio-spectrum'),
                        '-lpulse-simple', '-lpulse', '-lfftw3', '-lm'], check=True)
        put(payload, config / 'quickshell', Path('config/quickshell'))

    for script in sorted((repo / 'bin').iterdir()):
        put(script, home / '.local/bin' / script.name, Path('.local/bin') / script.name)

    for desktop in sorted((repo / 'assets/applications').glob('*.desktop')):
        put(desktop, home / '.local/share/applications' / desktop.name,
            Path('.local/share/applications') / desktop.name)

    for wallpaper in sorted((repo / 'assets/wallpapers').iterdir()):
        if wallpaper.is_file():
            put(wallpaper, home / 'Pictures/Wallpapers' / wallpaper.name,
                Path('Pictures/Wallpapers') / wallpaper.name)
    # Fedora has no Arch ttf-go-nerd package; keep shell glyphs available offline.
    data = Path(os.environ.get('XDG_DATA_HOME') or home / '.local/share')
    fonts = repo / 'assets/fonts'
    if fonts.is_dir():
        for font in sorted(fonts.iterdir()):
            if font.suffix in ('.ttf', '.txt'):
                put(font, data / 'fonts/hyprshell' / font.name,
                    Path('fonts/hyprshell') / font.name)
    put(repo / 'config/hyprshell/hyprland', config / 'hyprshell/hyprland',
        Path('config/hyprshell/hyprland'))
    for name in ('settings.json', 'cleanup.json', 'keybindings.json', 'keybindings.lua', 'displays.json', 'displays.lua', 'theme.json', 'applications.json', 'regional.json', 'behavior.json'):
        if (repo / 'config/hyprshell' / name).exists():
            put(repo / 'config/hyprshell' / name, config / 'hyprshell' / name, Path('config/hyprshell') / name)
    with tempfile.TemporaryDirectory(prefix='hyprshell-overrides-') as temporary:
        generated = Path(temporary) / 'overrides.lua'
        generated.write_text(overrides)
        put(generated, config / 'hyprshell/overrides.lua', Path('config/hyprshell/overrides.lua'))
    if behavior_source is not None:
        with tempfile.TemporaryDirectory(prefix='hyprshell-behavior-') as temporary:
            generated = Path(temporary) / 'behavior.lua'
            generated.write_text(behavior_source)
            put(generated, config / 'hyprshell/behavior.lua', Path('config/hyprshell/behavior.lua'))
    state.joinpath('hyprshell').mkdir(parents=True, exist_ok=True)
    state.joinpath('hyprshell/repository').write_text(str(repo.resolve()) + '\n')
    if (config / 'hyprshell/regional.json').exists():
        restored = subprocess.run(['python3', str(config / 'quickshell/settings/regional.py'), '--restore'], capture_output=True, text=True)
        if restored.returncode:
            print('Regional preferences need review:', restored.stdout.strip())
    if (config / 'hyprshell/applications.json').exists():
        # Restore at install time so startup choices are present before UWSM's generator.
        restored = subprocess.run(['python3', str(config / 'quickshell/settings/applications.py'), '--restore'], capture_output=True, text=True)
        if restored.returncode:
            print('Application preferences will be retried at login:', restored.stdout.strip())
        else:
            result = json.loads(restored.stdout)
            if result.get('skipped'):
                print('Application choices skipped because entries are unavailable:', ', '.join(result['skipped']))
    if backup.exists():
        print('Backup directory:', backup)


if __name__ == '__main__':
    install(Path(sys.argv[1]).resolve())
