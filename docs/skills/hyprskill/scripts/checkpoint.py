#!/usr/bin/env python3
"""Private, explicit-path file checkpoints with conflict-checked rollback."""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def canonical(path):
    # Resolve parent links, but preserve a final symlink as an object of its own.
    p = Path(os.path.abspath(path))
    return p.parent.resolve() / p.name


def capture(path):
    p = Path(path)
    if canonical(p) != p:
        raise ValueError(f'Parent path changed: {p}')
    try:
        info = p.lstat()
    except FileNotFoundError:
        return {'kind': 'absent'}
    if stat.S_ISLNK(info.st_mode):
        return {'kind': 'symlink', 'target': os.readlink(p)}
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f'List individual regular files or symlinks, not directories/devices: {p}')
    if info.st_nlink != 1:
        raise ValueError(f'Use a metadata-aware native backup for hard-linked files: {p}')
    data = p.read_bytes()
    result = {'kind': 'file', 'mode': stat.S_IMODE(info.st_mode),
              'uid': info.st_uid, 'gid': info.st_gid,
              'sha256': hashlib.sha256(data).hexdigest(),
              'data': base64.b64encode(data).decode('ascii')}
    if p.lstat() != info:
        # Reading may update atime, so compare only write-related attributes.
        now = p.lstat()
        if (info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns) != (
                now.st_ino, now.st_size, now.st_mtime_ns, now.st_ctime_ns):
            raise ValueError(f'File changed during capture: {p}')
    return result


def verify(entry):
    if entry['kind'] == 'file':
        data = base64.b64decode(entry['data'], validate=True)
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Checkpoint checksum mismatch')


def write_json(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.checkpoint-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def create(label, paths):
    files = {str(canonical(p)): capture(canonical(p)) for p in paths}
    for entry in files.values():
        verify(entry)
    root = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    root = root / 'hyprshell/agent-backups'
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-')
    folder = Path(tempfile.mkdtemp(prefix=stamp, dir=root))
    write_json(folder / 'before.json', {'version': 1, 'task': label, 'files': files})
    # Read back every byte before declaring the checkpoint ready.
    load(folder)
    return folder


def load(folder):
    data = json.loads((folder / 'before.json').read_text())
    if data['version'] != 1 or not data['files']:
        raise ValueError('Unsupported or empty checkpoint')
    for path, entry in data['files'].items():
        if not Path(path).is_absolute() or canonical(path) != Path(path):
            raise ValueError(f'Changed or invalid checkpoint path: {path}')
        verify(entry)
    return data


def record_after(folder):
    before = load(folder)
    after = {p: capture(p) for p in before['files']}
    write_json(folder / 'after.json', after)


def replace(path, entry):
    p = Path(path)
    if entry['kind'] == 'absent':
        p.unlink(missing_ok=True)
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=p.parent, prefix='.hyprskill-restore-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            if entry['kind'] == 'file':
                stream.write(base64.b64decode(entry['data'], validate=True))
                stream.flush()
                current = os.fstat(stream.fileno())
                if (current.st_uid, current.st_gid) != (entry['uid'], entry['gid']):
                    os.fchown(stream.fileno(), entry['uid'], entry['gid'])
                os.fchmod(stream.fileno(), entry['mode'])
                os.fsync(stream.fileno())
        if entry['kind'] == 'symlink':
            os.unlink(name)
            os.symlink(entry['target'], name)
        os.replace(name, p)
    finally:
        if os.path.lexists(name):
            os.unlink(name)


def restore(folder, apply=False):
    before = load(folder)['files']
    after_path = folder / 'after.json'
    after = json.loads(after_path.read_text()) if after_path.exists() else {}
    pending = []
    for path, original in before.items():
        current = capture(path)
        if current == original:
            print(f'Unchanged: {path}')
            continue
        if path not in after or current != after[path]:
            raise ValueError(f'Unrecorded or newer edits; reconcile manually: {path}')
        pending.append((path, original, current))
        print(f'Would restore: {path}')
    if not apply or not pending:
        return
    # Preflight all paths before any writes, and retain an undo checkpoint.
    undo = create(f'Before rollback of {folder}', [p for p, _, _ in pending])
    print(f'Rollback safety checkpoint: {undo}', flush=True)
    undo_after = {p: expected for p, _, expected in pending}
    write_json(undo / 'after.json', undo_after)
    for path, original, expected in pending:
        if capture(path) != expected:
            raise ValueError(f'File changed during rollback: {path}')
        replace(path, original)
        if capture(path) != original:
            raise ValueError(f'Could not verify restored file: {path}')
        # Only claim writes actually completed; never adopt a concurrent edit.
        undo_after[path] = original
        write_json(undo / 'after.json', undo_after)
        print(f'Restored: {path}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    new = commands.add_parser('create')
    new.add_argument('--label', required=True)
    new.add_argument('paths', nargs='+')
    after = commands.add_parser('record-after')
    after.add_argument('checkpoint', type=Path)
    recovery = commands.add_parser('restore', help='preview by default')
    recovery.add_argument('checkpoint', type=Path)
    recovery.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'create':
            print(create(args.label, args.paths))
        elif args.command == 'record-after':
            record_after(args.checkpoint)
        else:
            restore(args.checkpoint, args.apply)
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f'Checkpoint error: {exc}\n')


if __name__ == '__main__':
    main()
