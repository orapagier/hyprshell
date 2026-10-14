#!/usr/bin/env python3
"""Private personal-config checkpoints. Restore files without executing saved Lua."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
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


def snapshot_folder(ident):
    if not isinstance(ident, str) or not re.fullmatch(r'(?:configuration|setup)-[0-9-]+', ident):
        raise ValueError('Choose a Hyprshell setup backup from the list.')
    return roots()[1] / ('setup-backups' if ident.startswith('setup-') else 'backups') / ident


def metadata(folder):
    path = folder / 'metadata.json'
    if not safe(path) or not path.is_file() or path.stat().st_size > 10000:
        raise ValueError('Backup information is missing or unsafe.')
    data = json.loads(path.read_text())
    if (not isinstance(data, dict) or data.get('version') != 1 or
            data.get('kind') not in ('manual', 'before-restore') or
            not isinstance(data.get('createdAt'), str) or
            not isinstance(data.get('checksum'), str) or not re.fullmatch('[0-9a-f]{64}', data['checksum']) or
            type(data.get('fileCount')) is not int or not 0 <= data['fileCount'] <= 300 or
            type(data.get('bytes')) is not int or not 0 <= data['bytes'] <= 10_000_000):
        raise ValueError('Backup information is invalid.')
    created = datetime.fromisoformat(data['createdAt'])
    if created.tzinfo is None:
        raise ValueError('Backup date is missing its timezone.')
    return data


def save_snapshot(files, kind='manual'):
    validate(files)
    base = roots()[1] / 'setup-backups'
    if not safe(base): raise ValueError('Backup folders must not be symbolic links.')
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    created = datetime.now().astimezone()
    ident = 'setup-' + created.strftime('%Y%m%d-%H%M%S-%f')
    details = dict(version=1, createdAt=created.isoformat(timespec='microseconds'), kind=kind,
                   checksum=digest(files), fileCount=sum(value is not None for value in files.values()),
                   bytes=sum(len(value.encode()) for value in files.values() if value is not None))
    staging = tempfile.mkdtemp(prefix='.pending-', dir=base)
    try:
        folder = base / ident
        backend.atomic(Path(staging) / 'files.json', json.dumps(files, indent=2, ensure_ascii=False))
        backend.atomic(Path(staging) / 'metadata.json', json.dumps(details, indent=2))
        os.rename(staging, folder)
    finally:
        if os.path.exists(staging): shutil.rmtree(staging)
    return ident


def read_snapshot(ident):
    folder = snapshot_folder(ident)
    path = folder / 'files.json'
    if not safe(path) or not path.is_file() or path.stat().st_size > 64_000_000: raise ValueError('Checkpoint is missing or unsafe. Refresh the list.')
    files = validate(json.loads(path.read_text()))
    if ident.startswith('setup-') and digest(files) != metadata(folder)['checksum']:
        raise ValueError('Backup contents failed their checksum. Choose another backup.')
    return files


def backup_info(folder):
    if folder.name.startswith('setup-'):
        details = metadata(folder)
        created = datetime.fromisoformat(details['createdAt']).astimezone()
        kind = details['kind']
    else:
        created = datetime.strptime(folder.name.removeprefix('configuration-'), '%Y%m%d-%H%M%S-%f').astimezone()
        kind = 'legacy'
        details = dict(createdAt=created.isoformat(), fileCount=None, bytes=(folder / 'files.json').stat().st_size)
    kind_label = {'manual': 'Manual backup', 'before-restore': 'Before restore', 'legacy': 'Legacy checkpoint'}[kind]
    return dict(id=folder.name, label=created.strftime('%Y-%m-%d %H:%M:%S %Z (UTC%z)') + ' · ' + kind_label,
                createdAt=details['createdAt'], timestamp=created.timestamp(), kind=kind,
                fileCount=details['fileCount'], bytes=details['bytes'])


def status():
    _, state = roots(); rows = []
    skipped = 0
    for parent, pattern in ((state / 'setup-backups', 'setup-*'), (state / 'backups', 'configuration-*')):
        if not safe(parent): raise ValueError('Backup folders must not be symbolic links.')
        for folder in parent.glob(pattern):
            if not re.fullmatch(r'(?:configuration|setup)-[0-9-]+', folder.name): continue
            try:
                snapshot_folder(folder.name)
                if not safe(folder) or not (folder / 'files.json').is_file():
                    raise ValueError('Incomplete backup')
                rows.append(backup_info(folder))
            except (ValueError, OSError, TypeError, KeyError):
                skipped += 1
    rows.sort(key=lambda row: (row['timestamp'], row['id']), reverse=True)
    return {'ok': True, 'checkpoints': rows, 'revision': digest(current()),
            'backupDirectory': str(state / 'setup-backups'), 'skippedBackups': skipped}


def request(payload):
    operation = payload.get('operation'); _, state = roots()
    if operation == 'status': return status()
    with backend.lock(state / 'configuration.lock'):
        before = current()
        if operation == 'checkpoint':
            if payload.get('expected') != digest(before): raise ValueError('Configuration changed elsewhere. Refresh first.')
            validate(before)
            ident = save_snapshot(before)
            return {**status(), 'createdBackup': ident, 'message': 'Hyprshell setup backup saved with its date, time and checksum. Manual backups are preserved by system cleanup.'}
        if operation == 'preview':
            files = normalized(read_snapshot(payload.get('id')))
            changes = [name for name in sorted(set(before) | set(files)) if before.get(name) != files.get(name)]
            token = secrets.token_hex(24)
            backend.atomic(state / 'configuration-preview.json', json.dumps({'token': token, 'id': payload['id'], 'before': digest(before), 'after': digest(files), 'created': time.time()}))
            details = backup_info(snapshot_folder(payload['id']))
            return {**status(), 'preview': {'token': token, 'changes': changes, 'id': payload['id'], 'label': details['label']}}
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
            undo = save_snapshot(before, 'before-restore')
            transaction({config / name: files.get(name) for name in set(before) | set(files)}, 'configuration-undo')
            record_path.unlink(missing_ok=True)
            data = json.loads(files['hyprshell/settings.json']) if files.get('hyprshell/settings.json') else backend.DEFAULTS
            return {**status(), 'createdBackup': undo, 'restored': backend.validate(data), 'message': 'Hyprshell setup restored from ' + backup_info(snapshot_folder(record['id']))['label'] + '. A dated before-restore backup preserves the previous setup. Settings preferences reload now; log out and back in to apply compositor and application configuration.'}
    raise ValueError('Unknown configuration operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json', required=True); args = parser.parse_args()
    try: result = request(json.loads(args.request_json))
    except (ValueError, OSError, TypeError, KeyError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'Could not access this configuration checkpoint. Refresh and retry.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__': raise SystemExit(main())
