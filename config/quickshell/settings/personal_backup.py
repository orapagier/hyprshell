#!/usr/bin/env python3
"""Opt-in local personal-file snapshots with explicit scheduling and verification."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import time

from backend import atomic, lock
from preferences import roots, transaction

DEFAULTS = {'version': 1, 'destination': '', 'sources': [], 'schedule': 'off', 'device': None, 'inode': None}


def private_state(): return roots()[1] / 'personal-files.json'
def saved(): return json.loads(private_state().read_text()) if private_state().exists() else dict(DEFAULTS)


def safe(path): return not any(part.is_symlink() for part in (path, *path.parents))


@contextmanager
def job_lock():
    _, state = roots(); state.mkdir(parents=True, exist_ok=True)
    with (state / 'personal-files-run.lock').open('a') as stream:
        try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('A personal-file backup is running. Wait for it to finish and refresh.') from None
        yield


def validate(data, require_destination=False):
    if not isinstance(data, dict) or set(data) != set(DEFAULTS) or type(data['version']) is not int or data['version'] != 1 or data['schedule'] not in ('off', 'daily', 'weekly'):
        raise ValueError('Invalid personal backup preferences.')
    if not isinstance(data['destination'], str) or any(c in data['destination'] for c in '\n\r\0') or not isinstance(data['sources'], list) or len(data['sources']) > 20:
        raise ValueError('Choose a local backup folder and at most 20 source folders.')
    if len(set(data['sources'])) != len(data['sources']): raise ValueError('Source folders must be unique.')
    source_paths = []
    home = Path.home().resolve()
    for value in data['sources']:
        if not isinstance(value, str) or any(c in value for c in '\n\r\0'): raise ValueError('Invalid source folder.')
        path = Path(value)
        if not path.is_absolute() or path != path.resolve() or not safe(path) or not path.is_dir() or path == home or path == Path('/') or not path.is_relative_to(home) or any(part.startswith('.') for part in path.relative_to(home).parts):
            raise ValueError('Choose existing non-hidden personal folders inside your home. Symbolic links are excluded.')
        source_paths.append(path)
    for index, path in enumerate(source_paths):
        if any(path.is_relative_to(other) or other.is_relative_to(path) for other in source_paths[index + 1:]): raise ValueError('Choose source folders that do not contain each other.')
    if data['destination']:
        destination = Path(data['destination'])
        if not destination.is_absolute() or destination != destination.resolve() or not safe(destination) or not destination.is_dir() or not os.access(destination, os.W_OK | os.X_OK):
            raise ValueError('Connect the backup drive and choose an existing writable local folder. It will not be created automatically.')
        if any(destination.is_relative_to(source) or source.is_relative_to(destination) for source in source_paths): raise ValueError('Backup and source folders must be separate.')
        if require_destination and (destination.stat().st_dev != data['device'] or destination.stat().st_ino != data['inode']):
            raise ValueError('The backup folder or mounted drive changed. Reconnect it or save the destination again.')
    elif require_destination or data['schedule'] != 'off': raise ValueError('Choose an existing backup destination before running or scheduling backups.')
    if (require_destination or data['schedule'] != 'off') and not source_paths: raise ValueError('Choose at least one personal source folder.')
    return data


def timer_files(data):
    config, state = roots(); folder = config / 'systemd/user'
    service = folder / 'hyprshell-backup.service'; timer = folder / 'hyprshell-backup.timer'
    if data['schedule'] == 'off': return {service: None, timer: None}
    # systemd uses its own argument parser; quote paths and escape specifiers.
    executable = shlex.quote(sys.executable).replace('%', '%%').replace('$', '$$')
    helper = shlex.quote(str(Path(__file__).resolve())).replace('%', '%%').replace('$', '$$')
    if any(c in executable + helper for c in '\n\r\0'): raise ValueError('Unsupported backup helper path.')
    environment = 'Environment=' + json.dumps('XDG_CONFIG_HOME=' + str(config), ensure_ascii=False).replace('%', '%%') + ' ' + json.dumps('XDG_STATE_HOME=' + str(state.parent), ensure_ascii=False).replace('%', '%%') + '\n'
    return {service: '[Unit]\nDescription=Hyprshell personal-file backup\n\n[Service]\nType=oneshot\nExecStart=' + executable + ' ' + helper + ' --run\n' + environment + 'TimeoutStartSec=infinity\nNice=10\nIOSchedulingClass=idle\nUMask=0077\n',
            timer: '[Unit]\nDescription=Hyprshell personal-file backup schedule\n\n[Timer]\nOnCalendar=' + data['schedule'] + '\nPersistent=true\nRandomizedDelaySec=15m\n\n[Install]\nWantedBy=timers.target\n'}


def systemctl(*args):
    result = subprocess.run(['systemctl', '--user', *args], capture_output=True, text=True, timeout=15)
    if result.returncode: raise ValueError('The user service manager could not update the backup schedule. Retry in the desktop session.')


def configure(data, expected):
    data = dict(validate(data)); _, state = roots()
    with job_lock(), lock(state / 'personal-backup-settings.lock'):
        before = saved()
        if before != expected: raise ValueError('Backup preferences changed elsewhere. Refresh before saving.')
        if data['destination']:
            info = Path(data['destination']).stat(); data.update(device=info.st_dev, inode=info.st_ino)
        else: data.update(device=None, inode=None)
        changes = timer_files(data); changes[private_state()] = json.dumps(data, indent=2)
        def activate():
            if before['schedule'] != 'off' or data['schedule'] != 'off':
                systemctl('daemon-reload')
                systemctl('enable' if data['schedule'] != 'off' else 'disable', '--now', 'hyprshell-backup.timer')
        try: transaction(changes, 'personal-backup-policy', activate)
        except Exception:
            try:
                systemctl('daemon-reload')
                systemctl('enable' if before['schedule'] != 'off' else 'disable', '--now', 'hyprshell-backup.timer')
            except Exception: pass
            raise
    return data


def write_status(phase, **values):
    atomic(roots()[1] / 'personal-files-status.json', json.dumps({'phase': phase, 'time': datetime.now(timezone.utc).isoformat(), **values}))


def backup_root(data, create=False):
    validate(data, require_destination=True)
    folder = Path(data['destination']) / 'HyprshellBackups'
    if not safe(folder): raise ValueError('Backup folders must not be symbolic links.')
    marker = folder / '.hyprshell-backup.json'
    if folder.exists():
        if not safe(marker) or not marker.is_file() or json.loads(marker.read_text()).get('version') != 1:
            raise ValueError('The destination already contains an unrelated HyprshellBackups folder. Choose another folder.')
    elif create:
        folder.mkdir(mode=0o700); atomic(marker, json.dumps({'version': 1}))
    else: raise ValueError('No personal-file snapshot has been created yet.')
    return folder


def hash_file(path):
    if not safe(path): raise ValueError('A backup file became a symbolic link. Verification stopped.')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode): raise ValueError('Only regular files are backed up.')
        digest = hashlib.sha256()
        while chunk := stream.read(1024 * 1024): digest.update(chunk)
        after = os.fstat(stream.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns): raise ValueError('A source file changed during backup. Save your work and retry.')
    return digest.hexdigest(), before


def snapshots(folder):
    return sorted((path for path in folder.glob('snapshot-*') if safe(path) and path.is_dir() and (path / 'manifest.json').is_file()), reverse=True)


def run_backup():
    _, state = roots(); state.mkdir(parents=True, exist_ok=True)
    with (state / 'personal-files-run.lock').open('w') as stream:
        try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: return 0
        staging = None
        try:
            try: os.nice(10)
            except OSError: pass
            write_status('running', message='Copying selected personal folders…')
            data = saved(); folder = backup_root(data, create=True)
            previous = snapshots(folder)
            old = json.loads((previous[0] / 'manifest.json').read_text()) if previous else {'files': {}}
            ident = 'snapshot-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            staging = folder / ('.pending-' + secrets.token_hex(8)); staging.mkdir(mode=0o700)
            manifest = {'version': 1, 'created': datetime.now(timezone.utc).isoformat(), 'sources': data['sources'], 'files': {}, 'skipped': 0}
            total = 0
            for source_text in data['sources']:
                source = Path(source_text)
                prefix = hashlib.sha256(source_text.encode()).hexdigest()[:10] + '-' + source.name
                for directory, dirs, names in os.walk(source, followlinks=False):
                    parent = Path(directory)
                    if not safe(parent): raise ValueError('A source folder became a symbolic link. Backup stopped.')
                    linked = [name for name in dirs if (parent / name).is_symlink()]
                    manifest['skipped'] += len(linked); dirs[:] = [name for name in dirs if name not in linked]
                    relative_dir = Path(prefix) / parent.relative_to(source)
                    (staging / relative_dir).mkdir(parents=True, exist_ok=True, mode=0o700)
                    for name in names:
                        path = parent / name
                        if path.is_symlink() or not path.is_file(): manifest['skipped'] += 1; continue
                        digest, info = hash_file(path); relative = str(relative_dir / name); target = staging / relative
                        old_entry = old['files'].get(relative)
                        prior = previous[0] / relative if previous else None
                        # Verify old content before reusing its inode. New snapshots
                        # are never linked to originals that apps may overwrite.
                        if old_entry and old_entry['sha256'] == digest and prior and safe(prior) and prior.is_file() and hash_file(prior)[0] == digest:
                            os.link(prior, target)
                        else:
                            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                            with os.fdopen(descriptor, 'rb') as original, target.open('xb') as output:
                                shutil.copyfileobj(original, output, 1024 * 1024)
                            target.chmod(0o600)
                            os.utime(target, ns=(info.st_atime_ns, info.st_mtime_ns))
                            if hash_file(target)[0] != digest: raise ValueError('A source changed during copying. Save your work and retry.')
                        manifest['files'][relative] = {'sha256': digest, 'size': info.st_size}; total += info.st_size
            atomic(staging / 'manifest.json', json.dumps(manifest, indent=2))
            # A replaced/unmounted target must not receive a misleading success.
            validate(data, require_destination=True)
            target = folder / ident; os.replace(staging, target); staging = None
            write_status('complete', snapshot=ident, files=len(manifest['files']), bytes=total, skipped=manifest['skipped'], message='Personal-file snapshot completed. Verify it before relying on it.')
            return 0
        except Exception:
            write_status('failed', message='Backup did not complete. Check the mounted destination, free space and source permissions, then retry. Previous snapshots are preserved.')
            return 1
        finally:
            if staging and safe(staging) and staging.exists(): shutil.rmtree(staging)


def verify_contents():
    folder = backup_root(saved()); rows = snapshots(folder)
    if not rows: raise ValueError('No completed personal backup snapshot found.')
    path = rows[0]; manifest_path = path / 'manifest.json'
    if not safe(manifest_path): raise ValueError('Unsafe backup manifest.')
    manifest = json.loads(manifest_path.read_text())
    for relative, entry in manifest['files'].items():
        candidate = path / relative
        if Path(relative).is_absolute() or '..' in Path(relative).parts or not candidate.is_file() or hash_file(candidate)[0] != entry['sha256']:
            raise ValueError('Backup verification failed. Preserve the snapshot, check the drive, and create a new backup.')
    write_status('verified', snapshot=path.name, files=len(manifest['files']), message='Latest snapshot contents match every recorded SHA-256 checksum.')
    return {'ok': True, 'message': 'Latest snapshot verified: ' + str(len(manifest['files'])) + ' files match their checksums.'}


def verify_latest():
    with job_lock():
        return verify_contents()


def status():
    data = saved(); record = roots()[1] / 'personal-files-status.json'
    result = json.loads(record.read_text()) if record.exists() else {'phase': 'none', 'message': 'No automatic personal-file backup has run.'}
    if result['phase'] == 'running':
        run_lock = roots()[1] / 'personal-files-run.lock'
        with run_lock.open('a') as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = {**result, 'phase': 'interrupted', 'message': 'The backup worker stopped before completion. Previous snapshots are preserved; retry.'}
            except BlockingIOError: pass
    folders = []
    for name in ('DOCUMENTS', 'PICTURES', 'DESKTOP', 'MUSIC', 'VIDEOS', 'DOWNLOAD'):
        fallback = {'DOCUMENTS': 'Documents', 'PICTURES': 'Pictures', 'DESKTOP': 'Desktop', 'MUSIC': 'Music', 'VIDEOS': 'Videos', 'DOWNLOAD': 'Downloads'}[name]
        result_path = None
        if shutil.which('xdg-user-dir'):
            response = subprocess.run(['xdg-user-dir', name], capture_output=True, text=True, timeout=5)
            if response.returncode == 0: result_path = response.stdout.strip()
        path = Path(result_path or Path.home() / fallback)
        if path != Path.home() and path.is_dir() and safe(path): folders.append({'path': str(path), 'name': fallback})
    return {'ok': True, 'settings': data, 'status': result, 'folders': folders}


def request(payload):
    operation = payload.get('operation')
    if operation == 'status': return status()
    if operation == 'save':
        configure(payload.get('settings'), payload.get('expected'))
        return {**status(), 'message': 'Backup preferences saved. Selected documents and backup paths stay local.'}
    if operation == 'run':
        backup_root(saved(), create=True)
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--run'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {**status(), 'message': 'Backup started. Refresh to check completion. You can close Settings.'}
    if operation == 'verify':
        result = verify_latest()
        return {**status(), **result}
    if operation == 'open':
        folder = backup_root(saved()); subprocess.Popen(['xdg-open', str(folder)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {'ok': True, 'message': 'Opening snapshots. Each snapshot contains ordinary files; copy needed files to a separate folder before replacing originals.'}
    raise ValueError('Unknown personal backup operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json'); parser.add_argument('--run', action='store_true'); args = parser.parse_args()
    if args.run: return run_backup()
    try: result = request(json.loads(args.request_json or '{"operation":"status"}'))
    except (ValueError, OSError, TypeError, KeyError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'Personal backup could not be accessed. Check the drive and refresh.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__': sys.exit(main())
