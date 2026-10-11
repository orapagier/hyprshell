#!/usr/bin/env python3
"""Private personal-config checkpoints. Restore files without executing saved Lua."""
import argparse
from datetime import datetime
import hashlib
import json
import re
import secrets
import subprocess
import time

import backend
import applications
import behavior
import cleanup
import displays
import keybindings
import regional
import theme
from preferences import roots, transaction

FIXED = ('hyprshell/settings.json', 'hyprshell/cleanup.json', 'hyprshell/keybindings.json',
         'hyprshell/displays.json', 'hyprshell/theme.json', 'hyprshell/applications.json',
         'hyprshell/regional.json', 'hyprshell/behavior.json', 'hyprshell/overrides.lua',
         'hyprshell/keybindings.lua', 'hyprshell/displays.lua', 'hyprshell/behavior.lua',
         'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini', 'uwsm/env-hyprland', 'xdg-terminals.list')


def allowed(name):
    if name in FIXED: return True
    return bool(re.fullmatch(r'(?:hypr|hyprshell/hyprland)/[A-Za-z0-9_.-]+\.(?:lua|conf)', name)
                or re.fullmatch(r'autostart/[A-Za-z0-9_.+-]+\.desktop', name)
                or re.fullmatch(r'(?:[A-Za-z0-9_-]+-)?mimeapps\.list', name))


def safe(path):
    return not any(part.is_symlink() for part in (path, *path.parents))


def current():
    config, _ = roots(); names = set(FIXED)
    for folder in ('hypr', 'hyprshell/hyprland', 'autostart'):
        parent = config / folder
        if not safe(parent): raise ValueError('Configuration folders must not be symbolic links for complete recovery.')
        if parent.is_dir(): names.update(str(path.relative_to(config)) for path in parent.iterdir() if allowed(str(path.relative_to(config))))
    names.update(path.name for path in config.glob('*mimeapps.list') if allowed(path.name))
    result = {}
    for name in sorted(names):
        path = config / name
        if not safe(path): raise ValueError('A managed configuration file is a symbolic link. Use its owning application to restore it.')
        if path.exists():
            if not path.is_file() or path.stat().st_size > 2_000_000: raise ValueError('A configuration file is too large for a checkpoint.')
            result[name] = path.read_text()
        else: result[name] = None
    return result


def digest(files): return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def validate(files):
    if not isinstance(files, dict) or len(files) > 300 or sum(len((value or '').encode()) for value in files.values() if isinstance(value, (str, type(None)))) > 10_000_000:
        raise ValueError('Invalid or oversized configuration checkpoint.')
    for name, value in files.items():
        if not isinstance(name, str) or not allowed(name) or (value is not None and (not isinstance(value, str) or len(value.encode()) > 2_000_000)):
            raise ValueError('The checkpoint contains an unsupported file.')
    for name, validator in {'settings': backend.validate, 'cleanup': cleanup.validate,
                            'displays': displays.validate, 'theme': theme.validate,
                            'applications': applications.validate, 'regional': regional.validate,
                            'behavior': behavior.validate}.items():
        value = files.get('hyprshell/' + name + '.json')
        if value is not None: validator(json.loads(value))
    value = files.get('hyprshell/keybindings.json')
    if value is not None:
        data = json.loads(value)
        if set(data) != {'version', 'entries'} or data['version'] != 1: raise ValueError('Invalid keybinding checkpoint.')
        keybindings.validate(data['entries'])
    return files


def normalized(files):
    files = dict(validate(files))
    data = json.loads(files['hyprshell/settings.json']) if files.get('hyprshell/settings.json') else backend.DEFAULTS
    data = backend.validate(data)
    files['hyprshell/overrides.lua'] = backend.render_hypr(data['hyprland'], True, data['accessibility'])
    for name, renderer in [('displays', displays.render), ('behavior', behavior.render)]:
        value = files.get('hyprshell/' + name + '.json')
        files['hyprshell/' + name + '.lua'] = renderer(json.loads(value)) if value else None
    value = files.get('hyprshell/keybindings.json')
    files['hyprshell/keybindings.lua'] = keybindings.render(keybindings.validate(json.loads(value)['entries'])) if value else None
    return files


def read_snapshot(ident):
    if not isinstance(ident, str) or not re.fullmatch(r'configuration-[0-9-]+', ident): raise ValueError('Choose a configuration checkpoint.')
    path = roots()[1] / 'backups' / ident / 'files.json'
    if not safe(path) or not path.is_file() or path.stat().st_size > 64_000_000: raise ValueError('Checkpoint is missing or unsafe. Refresh the list.')
    return validate(json.loads(path.read_text()))


def status():
    _, state = roots(); rows = []
    for folder in sorted((state / 'backups').glob('configuration-*'), reverse=True):
        if re.fullmatch(r'configuration-[0-9-]+', folder.name) and safe(folder) and (folder / 'files.json').is_file():
            rows.append({'id': folder.name, 'label': folder.name.removeprefix('configuration-')})
    return {'ok': True, 'checkpoints': rows[:100], 'revision': digest(current())}


def request(payload):
    operation = payload.get('operation'); _, state = roots()
    if operation == 'status': return status()
    with backend.lock(state / 'configuration.lock'):
        before = current()
        if operation == 'checkpoint':
            if payload.get('expected') != digest(before): raise ValueError('Configuration changed elsewhere. Refresh first.')
            validate(before)
            ident = 'configuration-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            backend.atomic(state / 'backups' / ident / 'files.json', json.dumps(before, indent=2, ensure_ascii=False))
            return {**status(), 'message': 'Complete personal configuration checkpoint saved locally.'}
        if operation == 'preview':
            files = normalized(read_snapshot(payload.get('id')))
            changes = [name for name in sorted(set(before) | set(files)) if before.get(name) != files.get(name)]
            token = secrets.token_hex(24)
            backend.atomic(state / 'configuration-preview.json', json.dumps({'token': token, 'id': payload['id'], 'before': digest(before), 'after': digest(files), 'created': time.time()}))
            return {**status(), 'preview': {'token': token, 'changes': changes}}
        if operation == 'restore':
            record_path = state / 'configuration-preview.json'
            if not safe(record_path): raise ValueError('Preview this checkpoint again.')
            record = json.loads(record_path.read_text())
            if not isinstance(payload.get('token'), str) or not secrets.compare_digest(payload['token'], record['token']) or not 0 <= time.time() - record['created'] <= 300 or record['before'] != digest(before):
                raise ValueError('Preview expired or configuration changed. Preview again.')
            files = normalized(read_snapshot(record['id']))
            if digest(files) != record['after']: raise ValueError('Checkpoint changed. Preview again.')
            # Parse each restored Lua file for syntax without executing it or
            # applying monitor geometry without the display rollback workflow.
            for name, value in files.items():
                if value is not None and name.endswith('.lua'):
                    result = subprocess.run(['luac', '-p', '-'], input=value, capture_output=True, text=True, timeout=10)
                    if result.returncode: raise ValueError('Invalid Lua in ' + name + '. Repair the checkpoint before restoring.')
            restored_settings = backend.validate(json.loads(files['hyprshell/settings.json']) if files.get('hyprshell/settings.json') else backend.DEFAULTS)
            backend.idle_dependencies(restored_settings['locking'], restored_settings['power'])
            backend.idle_dependencies(restored_settings['locking'], backend.effective_power(restored_settings['power'], True))
            config, _ = roots()
            if digest(current()) != record['before']: raise ValueError('Configuration changed during validation. Preview again.')
            undo = 'configuration-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            backend.atomic(state / 'backups' / undo / 'files.json', json.dumps(before, indent=2, ensure_ascii=False))
            transaction({config / name: files.get(name) for name in set(before) | set(files)}, 'configuration-undo')
            record_path.unlink(missing_ok=True)
            data = json.loads(files['hyprshell/settings.json']) if files.get('hyprshell/settings.json') else backend.DEFAULTS
            return {**status(), 'restored': backend.validate(data), 'message': 'Personal configuration restored with an undo backup. Settings preferences reload now; log out and back in to apply compositor and application configuration.'}
    raise ValueError('Unknown configuration operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json', required=True); args = parser.parse_args()
    try: result = request(json.loads(args.request_json))
    except (ValueError, OSError, TypeError, KeyError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'Could not access this configuration checkpoint. Refresh and retry.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__': raise SystemExit(main())
