#!/usr/bin/env python3
"""Interactive distribution upgrades and validated recovery of saved desktop settings.

Recovery never executes files from a backup. Only settings JSON is imported;
the normal settings transaction regenerates compositor overrides.
"""
import argparse
import system_packages
import shlex
from collections import deque
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

import backend


def roots():
    home = Path.home()
    return (Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config'),
            Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'hyprshell')


def read_json(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 2_000_000:
        raise ValueError('Backup is missing, too large, or a symbolic link. Refresh and choose another.')
    return json.loads(path.read_text())


def current():
    config, _ = roots()
    path = config / 'hyprshell/settings.json'
    return backend.validate(read_json(path) if path.exists() else backend.DEFAULTS)


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def revision():
    config, _ = roots()
    # Detect hand-edited generated files as well as changes to preferences.
    paths = ['hyprshell/settings.json', 'hyprshell/overrides.lua', 'hyprshell/overrides.conf',
             'hypr/hyprland.lua', 'hypr/hyprland.conf']
    return digest({name: (config / name).read_text() if (config / name).exists() else None for name in paths})


def snapshot(ident):
    config, state = roots()
    if not isinstance(ident, str) or not re.fullmatch(r'(?:settings|recovery)-[\w-]+', ident):
        raise ValueError('Choose a desktop settings backup from the list.')
    folder = state / 'backups' / ident
    if folder.is_symlink() or not folder.is_dir() or folder.parent.is_symlink():
        raise ValueError('Backup is unavailable. Refresh the list.')
    if ident.startswith('recovery-'):
        return backend.validate(read_json(folder / 'settings.json'))
    manifest = read_json(folder / 'manifest.json')
    if not isinstance(manifest, list):
        raise ValueError('Invalid backup manifest.')
    for entry in manifest:
        if entry.get('path') == str(config / 'hyprshell/settings.json'):
            if not entry.get('existed'):
                return backend.validate(backend.DEFAULTS)
            name = entry.get('file')
            if not isinstance(name, str) or not re.fullmatch(r'\d+', name):
                raise ValueError('Invalid settings backup file.')
            return backend.validate(read_json(folder / name))
    raise ValueError('This backup does not contain desktop settings.')


def backups():
    _, state = roots()
    root = state / 'backups'
    if not root.exists() or root.is_symlink():
        return []
    rows = []
    for path in sorted(root.iterdir(), key=lambda p: p.name, reverse=True):
        if not path.name.startswith(('settings-', 'recovery-')):
            continue
        try:
            snapshot(path.name)
            created = datetime.fromtimestamp(path.stat().st_mtime).strftime('%Y-%m-%d %H:%M:%S')
            rows.append({'id': path.name, 'label': created + (' · Checkpoint' if path.name.startswith('recovery-') else ' · Before settings change')})
        except (OSError, ValueError, TypeError, AttributeError, KeyError):
            continue
    return sorted(rows, key=lambda row: row['label'], reverse=True)[:100]


def checkpoint(expected):
    _, state = roots()
    if expected != revision():
        raise ValueError('Settings changed elsewhere. Refresh before creating a checkpoint.')
    data = current()
    ident = 'recovery-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backend.atomic(state / 'backups' / ident / 'settings.json', json.dumps(data, indent=2) + '\n')
    return ident


def preview(ident):
    _, state = roots()
    before, after = current(), snapshot(ident)
    labels = {'clipboard': 'Clipboard capture preferences', 'accessibility': 'Accessibility', 'bar': 'Hyprpane & panels', 'items': 'Hyprpane items', 'hyprland': 'Compositor, mouse & keyboard',
              'panels': 'Panel placement', 'pins': 'Pinned applications', 'locking': 'Screen locking', 'power': 'Power & battery', 'notifications': 'Notification delivery'}
    changes = [label for key, label in labels.items() if before[key] != after[key]]
    token = secrets.token_hex(24)
    record = {'id': ident, 'token': token, 'revision': revision(), 'current': before,
              'snapshot': digest(after), 'created': time.time()}
    backend.atomic(state / 'recovery-preview.json', json.dumps(record))
    return {'id': ident, 'token': token, 'changes': changes}


def restore(token):
    _, state = roots()
    record = read_json(state / 'recovery-preview.json')
    if not isinstance(token, str) or not secrets.compare_digest(token, record['token']):
        raise ValueError('Preview this backup again before restoring.')
    if not 0 <= time.time() - record['created'] <= 300 or record['revision'] != revision():
        raise ValueError('The preview expired or settings changed elsewhere. Preview again.')
    data = snapshot(record['id'])
    if digest(data) != record['snapshot']:
        raise ValueError('The backup changed after preview. Preview again.')
    result = backend.save(data, expected=record['current'])
    (state / 'recovery-preview.json').unlink(missing_ok=True)
    return result


def backup_status():
    _, state = roots()
    path = state / 'personal-backup.json'
    if not path.exists():
        return {'folder': '', 'confirmed': '', 'available': False}
    data = read_json(path)
    folder = Path(data['folder'])
    return {**data, 'available': folder.is_dir() and os.access(folder, os.R_OK | os.X_OK)}


def confirm_backup(folder):
    if not isinstance(folder, str) or not folder.strip() or any(c in folder for c in '\n\r\0'):
        raise ValueError('Enter the absolute path of the backup folder you checked.')
    path = Path(folder.strip()).expanduser()
    if not path.is_absolute() or not path.is_dir() or not os.access(path, os.R_OK | os.X_OK):
        raise ValueError('That backup folder is unavailable or unreadable. Connect the backup drive and try again.')
    _, state = roots()
    # A user report, never a claim that we backed up or verified their documents.
    backend.atomic(state / 'personal-backup.json', json.dumps({'folder': str(path),
                   'confirmed': datetime.now(timezone.utc).isoformat(timespec='seconds')}))


def update_status():
    _, state = roots()
    path = state / 'upgrade-last.json'
    if not path.exists():
        return {'status': 'none', 'message': 'No system upgrade has been run from Settings.'}
    data = read_json(path)
    if data['status'] == 'launching' and time.time() - data['time'] > 30:
        return {**data, 'status': 'unknown', 'message': 'The update window did not report a result. Check the terminal before trying again.'}
    if data['status'] == 'running':
        try:
            os.kill(data['pid'], 0)
        except ProcessLookupError:
            return {**data, 'status': 'unknown', 'message': 'The update window ended without reporting completion. Review the package manager log before retrying.'}
    return data


def write_update(status, message):
    _, state = roots()
    backend.atomic(state / 'upgrade-last.json', json.dumps({'status': status, 'message': message,
                   'time': time.time(), 'pid': os.getpid()}))


@contextmanager
def upgrade_lock():
    _, state = roots()
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'upgrade.lock').open('w') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('A system upgrade window is already open. Finish it before starting another.')
        yield


def update_error(output):
    text = output.lower()
    if 'unable to lock database' in text or 'database is locked' in text:
        return 'Another package manager is active or left a lock. Close it and retry; inspect the lock before removing it.'
    if 'signature' in text or 'keyring' in text or 'unknown trust' in text:
        return 'Package signature verification failed. Check the clock and follow your distribution’s package-signing recovery guide.'
    if 'space' in text and ('disk' in text or 'device' in text):
        return 'There is not enough disk space. Review System cleanup or move files, then retry the full upgrade.'
    if any(term in text for term in ('failed retrieving', 'could not resolve', 'failed to synchronize')):
        return 'Package servers could not be reached. Check your network and mirrors, then retry the full upgrade.'
    if 'exists in filesystem' in text or 'conflicting dependencies' in text or 'could not satisfy dependencies' in text:
        return 'A package or file conflict blocked the upgrade. Review the terminal and distribution news before retrying.'
    return 'The full upgrade did not complete. Review the terminal output and resolve the error before installing other packages.'


def check_updates():
    if system_packages.distribution() == 'fedora':
        if not shutil.which('dnf'):
            raise ValueError('DNF is required to check Fedora updates.')
        # An unprivileged check only updates the user's metadata cache.
        result = subprocess.run(['dnf', '--refresh', '--quiet', 'check-upgrade', '--json'],
                                capture_output=True, text=True,
                                env=dict(os.environ, LC_ALL='C'), timeout=120)
        if result.returncode not in (0, 100):
            raise ValueError('Could not check Fedora updates. Review your connection and enabled repositories.')
        packages = []
        if result.returncode == 100:
            try:
                sections = json.loads(result.stdout)
                packages = [f"{package['name']}.{package['arch']}  {package['evr']}  {package['repository']}"
                            for entries in sections.values() for package in entries]
            except (ValueError, KeyError, TypeError, AttributeError):
                raise ValueError('Could not read DNF update results. Update DNF5 and retry.') from None
        return {'packages': packages, 'checked': datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    if not shutil.which('checkupdates'):
        raise ValueError('Install pacman-contrib during a full system upgrade to enable update checks.')
    # Never refresh the system package database for a preview.
    with tempfile.TemporaryDirectory(prefix='hyprshell-checkupdates-') as temporary:
        env = dict(os.environ, CHECKUPDATES_DB=temporary, LC_ALL='C')
        result = subprocess.run(['checkupdates', '--nocolor'], capture_output=True, text=True, env=env, timeout=120)
    if result.returncode not in (0, 2):
        raise ValueError('Could not check updates. Check your internet connection and package mirrors, then retry.')
    packages = result.stdout.strip().splitlines() if result.returncode == 0 else []
    return {'packages': packages, 'checked': datetime.now().strftime('%Y-%m-%d %H:%M:%S')}


def launch_upgrade():
    for command in ('kitty', 'sudo', system_packages.upgrade_command()[1]):
        if not shutil.which(command):
            raise ValueError(f'{command} is required to open the system upgrade window.')
    _, state = roots()
    with upgrade_lock():
        if update_status()['status'] in ('launching', 'running'):
            raise ValueError('A system upgrade window is already open. Finish it before starting another.')
        write_update('launching', 'Opening the interactive upgrade window…')
        try:
            result = subprocess.run(['kitty', '--detach', '--title', 'Hyprshell system upgrade',
                                     sys.executable, str(Path(__file__).resolve()), '--upgrade-terminal'],
                                    capture_output=True, text=True, timeout=15)
            if result.returncode:
                raise ValueError('Could not open the update terminal. Try again from the desktop session.')
        except Exception:
            write_update('failed', 'Could not open the update terminal. Try again from the desktop session.')
            raise


def upgrade_terminal():
    _, state = roots()
    # Held for the whole terminal workflow, including the explicit review step.
    with upgrade_lock():
        write_update('running', 'System upgrade window is open. Review and complete it in the terminal.')
        metadata = system_packages.metadata()
        command = system_packages.upgrade_command()
        print('Hyprshell system upgrade\n\nRead ' + metadata['news'] + ' before upgrading.\n'
              'Save your work and check your personal backup.\n'
              'This upgrades all repository packages with ' + shlex.join(command) + '.\n'
              + metadata['foreign'] + '\n'
              'Your password and package confirmation stay in this terminal.\n')
        try:
            if input('Start the full system upgrade? [y/N] ').strip().lower() != 'y':
                write_update('cancelled', 'System upgrade cancelled before any package changes.')
                return 0
            env = dict(os.environ, LC_ALL='C')
            tail = deque(maxlen=80)
            with subprocess.Popen(command, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, env=env) as process:
                for line in process.stdout:
                    print(line, end='', flush=True)
                    tail.append(line)
                code = process.wait()
            message = 'Full system upgrade completed. Restart when convenient to load updated system components.' if code == 0 else update_error(''.join(tail))
            write_update('completed' if code == 0 else 'failed', message)
            print('\n' + message)
            input('Press Enter to close…')
            return code
        except (EOFError, KeyboardInterrupt):
            if update_status()['status'] == 'running':
                write_update('unknown', 'The upgrade was interrupted. Check the terminal and package manager log before retrying.')
            return 1
        except (OSError, subprocess.SubprocessError) as error:
            message = update_error(str(error))
            write_update('failed', message)
            print(message)
            try:
                input('Press Enter to close…')
            except EOFError:
                pass
            return 1


def status():
    return {'ok': True, 'backups': backups(), 'revision': revision(),
            'personal': backup_status(), 'upgrade': update_status(), 'system': system_packages.metadata()}


def request(payload):
    _, state = roots()
    operation = payload.get('operation')
    if operation == 'status':
        return status()
    if operation == 'check-updates':
        return {**status(), 'updates': check_updates()}
    if operation == 'upgrade':
        launch_upgrade()
        return {**status(), 'message': 'Review the full upgrade in the terminal. It stays open when Settings closes.'}
    with backend.lock(state / 'recovery.lock'):
        message = ''
        if operation == 'checkpoint':
            checkpoint(payload.get('expected'))
            message = 'Desktop settings checkpoint saved.'
        elif operation == 'preview':
            return {**status(), 'preview': preview(payload.get('id'))}
        elif operation == 'restore':
            result = restore(payload.get('token'))
            return {**status(), 'restored': current(), 'message': result['message']}
        elif operation == 'confirm-backup':
            confirm_backup(payload.get('folder'))
            message = 'Recorded your backup check. Document contents have not been verified by Hyprshell.'
        else:
            raise ValueError('Unknown recovery operation.')
        return {**status(), 'message': message}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--request-json')
    parser.add_argument('--upgrade-terminal', action='store_true')
    args = parser.parse_args()
    if args.upgrade_terminal:
        return upgrade_terminal()
    try:
        result = request(json.loads(args.request_json or '{"operation":"status"}'))
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error)}
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
