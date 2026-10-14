#!/usr/bin/env python3
"""User-scoped cleanup with a fresh, verifiable preview and no symlink traversal."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

DEFAULTS = dict(schedule='off', days=30, keep=5, thumbnails=True, temporary=True, backups=True)

def roots():
    home = Path.home()
    return (Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config'),
            Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state'),
            Path(os.environ.get('XDG_CACHE_HOME') or home / '.cache'))

def validate(data):
    if not isinstance(data, dict) or set(data) != set(DEFAULTS):
        raise ValueError('Invalid cleanup settings')
    if data['schedule'] not in ('off', 'daily', 'weekly', 'monthly'):
        raise ValueError('Invalid schedule')
    for key, low, high in [('days', 1, 365), ('keep', 1, 100)]:
        if type(data[key]) is not int or not low <= data[key] <= high:
            raise ValueError(f'{key} must be a whole number from {low} to {high}')
    for key in ('thumbnails', 'temporary', 'backups'):
        if type(data[key]) is not bool:
            raise ValueError('Cleanup categories must be boolean')
    return data

def read():
    path = roots()[0] / 'hyprshell/cleanup.json'
    return validate(json.loads(path.read_text())) if path.exists() else DEFAULTS.copy()

def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=20)

def status():
    enabled = run('systemctl', 'is-enabled', 'paccache.timer')
    active = run('systemctl', 'is-active', 'paccache.timer')
    timer = run('systemctl', '--user', 'is-active', 'hyprshell-cleanup.timer')
    return dict(ok=True, settings=read(), paccache=f'{enabled.stdout.strip() or "unavailable"} / {active.stdout.strip() or "unavailable"}', timer=timer.stdout.strip() or 'unavailable')

def secure_parent(path):
    # Every ancestor is opened without following links, including XDG roots.
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.absolute().parts[1:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise

def scan(settings):
    _, state, cache = roots()
    targets = []
    if settings['thumbnails']:
        targets.append(('Thumbnail cache', cache / 'thumbnails'))
    if settings['temporary']:
        targets.extend([('Temporary files', Path('/tmp')), ('Temporary files', Path('/var/tmp'))])
    if settings['backups']:
        backup = state / 'hyprshell/backups'
        if backup.is_dir() and not backup.is_symlink():
            groups = sorted((p for p in backup.iterdir() if p.is_dir() and not p.is_symlink()), key=lambda p: p.stat().st_mtime, reverse=True)
            targets.extend(('Hyprshell config backups', p) for p in groups[settings['keep']:])
    cutoff = time.time() - settings['days'] * 86400
    entries = []
    for category, root in targets:
        if root.is_symlink() or not root.is_dir():
            continue
        for directory, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(directory) / d).is_symlink()]
            for name in files:
                path = Path(directory) / name
                try:
                    fd = secure_parent(path)
                    try:
                        info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                    finally:
                        os.close(fd)
                    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or max(info.st_mtime, info.st_atime, info.st_ctime) >= cutoff:
                        continue
                    entries.append(dict(path=str(path), category=category, size=info.st_size, inode=info.st_ino, device=info.st_dev, mtime=info.st_mtime_ns, ctime=info.st_ctime_ns))
                except OSError:
                    continue
    return sorted(entries, key=lambda e: e['path'])

def token(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()

def preview():
    settings = read()
    entries = scan(settings)
    message = (f'{len(entries)} eligible files. Only old files owned by you; symlinks are skipped. Empty directories are retained.'
               if entries else f'No files match the saved {settings["days"]}-day age and backup-retention rules. '
               'This checks thumbnails, temporary files and backups only. Use Clean now · your files for browser and package caches.')
    return dict(ok=True, entries=entries, token=token(entries), bytes=sum(e['size'] for e in entries), message=message)

def clean(expected=None):
    entries = scan(read())
    if expected is not None and token(entries) != expected:
        raise ValueError('Files changed since the preview. Preview again before cleaning.')
    removed = 0
    failures = []
    for entry in entries:
        path = Path(entry['path'])
        try:
            fd = secure_parent(path)
            try:
                info = os.stat(path.name, dir_fd=fd, follow_symlinks=False)
                if (info.st_ino, info.st_dev, info.st_size, info.st_mtime_ns, info.st_ctime_ns) != (entry['inode'], entry['device'], entry['size'], entry['mtime'], entry['ctime']):
                    raise ValueError('File changed')
                os.unlink(path.name, dir_fd=fd)
                removed += 1
            finally:
                os.close(fd)
        except (OSError, ValueError) as error:
            failures.append(f'{path}: {error}')
    result = dict(ok=not failures, message=f'Cleaned {removed} files.' + (' Some files were skipped: ' + '\n'.join(failures) if failures else ''))
    state = roots()[1] / 'hyprshell/cleanup-last.json'
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(json.dumps(dict(result, time=time.time())))
    return result

def save(data):
    from backend import atomic
    data = validate(data)
    config, _, _ = roots()
    units = config / 'systemd/user'
    def quote(value):
        return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('$', '$$') + '"'
    command = quote(sys.executable) + ' ' + quote(Path(__file__).resolve()) + ' --scheduled'
    service = '[Unit]\nDescription=Hyprshell user cache cleanup\n[Service]\nType=oneshot\nExecStart=' + command + '\n'
    timer = '[Unit]\nDescription=Hyprshell scheduled cleanup\n[Timer]\nOnCalendar=' + (data['schedule'] if data['schedule'] != 'off' else 'weekly') + '\nPersistent=true\nRandomizedDelaySec=15m\n[Install]\nWantedBy=timers.target\n'
    paths = {units / 'hyprshell-cleanup.service': service, units / 'hyprshell-cleanup.timer': timer,
             config / 'hyprshell/cleanup.json': json.dumps(data, indent=2) + '\n'}
    previous = {p: p.read_text() if p.exists() else None for p in paths}
    old = read()
    try:
        for path, content in paths.items():
            atomic(path, content)
        for args in [('daemon-reload',), ('disable' if data['schedule'] == 'off' else 'enable', '--now', 'hyprshell-cleanup.timer')]:
            result = run('systemctl', '--user', *args)
            if result.returncode:
                raise ValueError(result.stderr.strip() or 'Could not update cleanup timer')
    except Exception:
        for path, content in previous.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                atomic(path, content)
        run('systemctl', '--user', 'daemon-reload')
        run('systemctl', '--user', 'disable' if old['schedule'] == 'off' else 'enable', '--now', 'hyprshell-cleanup.timer')
        raise
    return dict(status(), message='Cleanup settings saved.')


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--status', action='store_true')
    group.add_argument('--preview', action='store_true')
    group.add_argument('--clean')
    group.add_argument('--scheduled', action='store_true')
    group.add_argument('--save')
    args = parser.parse_args()
    try:
        from backend import lock
        with lock(roots()[1] / 'hyprshell/cleanup.lock'):
            if args.status:
                result = status()
            elif args.preview:
                result = preview()
            elif args.save:
                result = save(json.loads(args.save))
            elif args.scheduled:
                result = clean() if read()['schedule'] != 'off' else dict(ok=True, message='Scheduling is off.')
            else:
                result = clean(args.clean)
    except Exception as error:
        result = dict(ok=False, message=str(error))
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
