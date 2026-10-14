#!/usr/bin/env python3
"""Explicit cleanup plans, fixed administrator actions, and backed-up settings reset.

Manual choices never change the existing automatic cleanup timer. No operation
accepts arbitrary shell commands or recursively deletes application profiles.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import time

import backend
import cleanup
import recovery
import system_packages

MAX_FILES = 100000
EXPIRY = 300


def row(ident, title, paths, impact, risk='low', process='', policy='files'):
    return dict(id=ident, title=title, paths=[str(p) for p in paths], impact=impact,
                risk=risk, process=process, policy=policy)


def catalog(system=False):
    if system:
        distro = system_packages.distribution()
        package_path = '/var/cache/libdnf5' if distro == 'fedora' else '/var/cache/pacman/pkg'
        return [
            row('packages', 'System package cache', [package_path],
                'Affects package downloads and offline reinstalls. Installed packages stay installed. '
                + ('DNF removes all cached metadata and packages; later operations download them again.' if distro == 'fedora'
                   else 'paccache retains the newest two cached versions of each package.'), policy='command'),
            row('temporary', 'Expired system temporary files', ['/tmp', '/var/tmp'],
                'Affects temporary working files. systemd uses configured ages and exclusions; '
                'live sockets and boot-only removal rules are not selected.', policy='command'),
            row('journals', 'Old system journal archives', ['/var/log/journal'],
                'Affects troubleshooting history. Rotate logs, then keep archives for at most 14 days '
                'and 100 MiB. Active journals may exceed that size.', 'history', policy='command'),
            row('crashes', 'Old crash dumps', ['/var/lib/systemd/coredump'],
                'Affects crash debugging: removed dumps cannot be examined later.', 'history'),
            row('boot-backups', 'Older boot appearance backups', ['/var/lib/hyprshell/boot-backups'],
                'Affects rollback of boot splash configuration. Retain the newest selected number '
                'of backup sets. Installed boot configuration is preserved.', 'recovery', policy='backups'),
            row('appearance-backups', 'Older login appearance backups', ['/var/lib/hyprshell/appearance-backups'],
                'Affects rollback of login appearance. Retain the newest selected number of backup '
                'sets. Installed login configuration is preserved.', 'recovery', policy='backups'),
        ]
    _, state, cache = cleanup.roots()
    home = Path.home()
    return [
        row('chromium', 'Chromium cache', [cache / 'chromium'],
            'Affects cached web content: pages may load more slowly until downloaded again. '
            'Cookies, passwords, bookmarks and browser profiles are preserved.',
            process=r'(^|/)(chromium|chromium-browser)( |$)'),
        row('firefox', 'Firefox cache', [cache / 'mozilla/firefox'],
            'Affects cached web content. Firefox will rebuild it; saved logins and profiles are preserved.',
            process=r'(^|/)(firefox|firefox-bin)( |$)'),
        row('brave', 'Brave cache', [cache / 'BraveSoftware/Brave-Browser'],
            'Affects cached web content. Brave will rebuild it; saved logins and profiles are preserved.',
            process=r'(^|/)(brave|brave-browser)( |$)'),
        row('packages', 'Your package metadata cache', [cache / 'libdnf5'],
            'Affects package search/download speed. Metadata is downloaded again; installed software stays.',
            process=r'(^|/)(dnf|dnf5)( |$)'),
        row('npm', 'npm download cache', [home / '.npm/_cacache'],
            'Affects JavaScript package downloads and offline installs. Project files and dependencies stay.',
            process=r'(^|/)(npm|npx)( |$)'),
        row('thumbnails', 'File thumbnails', [cache / 'thumbnails'],
            'Affects file preview speed. Images and documents stay; thumbnails are generated again.'),
        row('flatpak-cache', 'Flatpak download metadata cache', [cache / 'flatpak'],
            'Affects application catalog/download speed. Flatpak regenerates this cache; installed apps and app data stay.'),
        row('trash', 'Empty desktop Trash', [Path(os.environ.get('XDG_DATA_HOME') or home / '.local/share') / 'Trash'],
            'Permanently removes discarded files, including Trash on mounted drives. You will lose '
            'the ability to restore them. The size shown covers home Trash only.', 'personal', policy='command'),
        row('graphics', 'Graphics and font caches', [cache / name for name in
            ('mesa_shader_cache', 'fontconfig', 'gtk-4.0', 'quickshell', 'qmltestrunner', 'qmltestrunner-qt6')],
            'Affects initial graphics, font and desktop rendering speed while caches rebuild. '
            'Themes, fonts and desktop settings stay.'),
        row('backups', 'Older Hyprshell configuration backups', [state / 'hyprshell/backups'],
            'Affects desktop recovery history. Retain the newest selected number of backup sets. '
            'Current settings and personal-file snapshots stay.', 'recovery', policy='backups'),
        row('chosen-folder', 'Backup / temporary copies in a chosen folder', [],
            'Affects recovery copies of your own files. Only .bak, .backup, .orig, .rej, .tmp '
            'and names ending in ~ are eligible. Review every path; these copies may be valuable. '
            'Browser databases, hidden folders, repositories and application state are excluded.', 'personal'),
    ]


def options(payload, system):
    selected = payload.get('selected', [])
    if (not isinstance(selected, list) or not selected or
            any(not isinstance(item, str) for item in selected) or len(set(selected)) != len(selected)):
        raise ValueError('Select at least one cleanup category.')
    rows = {item['id']: item for item in catalog(system)}
    if set(selected) - set(rows):
        raise ValueError('Unknown cleanup category.')
    days, keep = payload.get('days', 7 if system else 0), payload.get('keep', 5)
    if type(days) is not int or not 0 <= days <= 365:
        raise ValueError('File age must be a whole number from 0 to 365 days.')
    if type(keep) is not int or not 1 <= keep <= 100:
        raise ValueError('Keep between 1 and 100 backup sets.')
    folder = ''
    if 'chosen-folder' in selected:
        candidate = Path(payload.get('folder', '')).expanduser().absolute()
        try:
            relative = candidate.relative_to(Path.home())
        except ValueError:
            raise ValueError('Choose a non-hidden folder inside your home, such as Documents or Downloads.')
        if not relative.parts or any(part.startswith('.') for part in relative.parts) or relative.parts[0] == 'repos':
            raise ValueError('Full home, hidden folders and repositories cannot be selected.')
        with_directory(candidate)  # Refuse symlinked roots and ancestors.
        folder = str(candidate)
    return dict(selected=sorted(selected), days=days, keep=keep, folder=folder)


def with_directory(path):
    fd = cleanup.secure_parent(Path(path) / '_entry')
    os.close(fd)


def active(pattern):
    if not pattern:
        return False
    if not shutil.which('pgrep'):
        return True
    result = subprocess.run(['pgrep', '-u', str(os.getuid()), '-f', pattern],
                            capture_output=True, timeout=10)
    return result.returncode != 1


def scan_tree(path, ident, days, system=False, suffixes=False):
    entries, errors = [], []
    try:
        fd = cleanup.secure_parent(Path(path) / '_entry')
    except FileNotFoundError:
        return entries, errors
    except OSError as exc:
        return entries, [f'{path}: {exc}']
    cutoff = time.time() - days * 86400
    def failed(exc):
        errors.append(str(exc))
    try:
        root = os.fstat(fd)
        if not system and root.st_uid != os.getuid():
            return [], [f'{path}: owned by another user']
        for directory, dirs, files, current_fd in os.fwalk('.', dir_fd=fd, follow_symlinks=False, onerror=failed):
            # Never descend into repositories when reviewing personal copies.
            if suffixes and any((Path(path) / directory / marker).exists() for marker in ('.git', '.hg', '.svn')):
                dirs[:] = []
                continue
            for name in dirs[:]:
                try:
                    info = os.stat(name, dir_fd=current_fd, follow_symlinks=False)
                    if (not stat.S_ISDIR(info.st_mode) or info.st_dev != root.st_dev or
                        (not system and info.st_uid != os.getuid()) or
                        (suffixes and name.startswith('.')) or
                        os.path.ismount(f'/proc/self/fd/{current_fd}/{name}')):
                        dirs.remove(name)
                except OSError as exc:
                    dirs.remove(name)
                    failed(exc)
            for name in files:
                if suffixes and (name.startswith('.') or not name.endswith(('.bak', '.backup', '.orig', '.rej', '.tmp', '~'))):
                    continue
                try:
                    info = os.stat(name, dir_fd=current_fd, follow_symlinks=False)
                    if not stat.S_ISREG(info.st_mode) or info.st_dev != root.st_dev:
                        continue
                    if not system and info.st_uid != os.getuid():
                        continue
                    if days and max(info.st_atime, info.st_mtime, info.st_ctime) >= cutoff:
                        continue
                    entries.append(dict(path=str(Path(path) / directory / name), category=ident,
                        size=info.st_size, inode=info.st_ino, device=info.st_dev, uid=info.st_uid,
                        mtime=info.st_mtime_ns, ctime=info.st_ctime_ns))
                    if len(entries) > MAX_FILES:
                        raise ValueError('Too many files for one preview. Select fewer categories or a smaller folder.')
                except OSError as exc:
                    failed(exc)
    finally:
        os.close(fd)
    return entries, errors


def backup_roots(path, keep):
    try:
        with_directory(path)
        groups = [p for p in Path(path).iterdir() if not p.is_symlink() and p.is_dir()]
        return sorted(groups, key=lambda p: (p.stat().st_mtime_ns, p.name), reverse=True)[keep:]
    except FileNotFoundError:
        return []


def command_for(ident):
    if ident == 'trash':
        return ['/usr/bin/gio', 'trash', '--empty']
    if ident == 'packages':
        return (['/usr/bin/dnf', 'clean', 'all'] if system_packages.distribution() == 'fedora'
                else ['/usr/bin/paccache', '-rk2'])
    if ident == 'temporary':
        return ['/usr/bin/systemd-tmpfiles', '--clean', '--prefix=/tmp', '--prefix=/var/tmp']
    if ident == 'journals':
        return ['/usr/bin/journalctl', '--rotate', '--vacuum-time=14d', '--vacuum-size=100M']
    raise ValueError('Unknown system maintenance action.')


def plan(choice, system=False):
    all_entries, groups, warnings = [], [], []
    rows = {item['id']: item for item in catalog(system)}
    for ident in choice['selected']:
        item = dict(rows[ident])
        paths = [Path(p) for p in item['paths']]
        if ident == 'chosen-folder':
            paths = [Path(choice['folder'])]
            item['paths'] = [choice['folder']]
        entries, errors = [], []
        blocked = active(item['process']) if not system else False
        if blocked:
            errors.append('Close the related application and preview again; this category is skipped.')
        elif item['policy'] == 'command':
            item['command'] = command_for(ident)
            if not Path(item['command'][0]).exists():
                errors.append('Required maintenance tool is not installed; this category is skipped.')
                blocked = True
            # Observed size is an upper bound, not a promise of what policy tools remove.
            if ident != 'temporary':
                for path in paths:
                    found, issues = scan_tree(path, ident, 0, system)
                    entries.extend(found); errors.extend(issues)
        else:
            try:
                if item['policy'] == 'backups':
                    paths = [p for path in paths for p in backup_roots(path, choice['keep'])]
                for path in paths:
                    found, issues = scan_tree(path, ident, choice['days'], system, ident == 'chosen-folder')
                    entries.extend(found); errors.extend(issues)
            except OSError as exc:
                errors.append(str(exc))
        item.update(count=len(entries), bytes=sum(e['size'] for e in entries), blocked=blocked,
                    warnings=errors[:20], estimate=item['policy'] == 'command')
        if not entries and not blocked and item['policy'] != 'command':
            item['emptyReason'] = (
                f'No files match the age/retention rules; the newest {choice["keep"]} backup sets are kept.'
                if item['policy'] == 'backups' else
                f'No matching files untouched for {choice["days"]} days. Set minimum age to 0 to include recent files.'
                if choice['days'] else 'No eligible regular files were found in this directory.')
        groups.append(item)
        if item['policy'] != 'command':
            all_entries.extend(entries)
        warnings.extend(errors)
        if len(all_entries) > MAX_FILES:
            raise ValueError('Too many files for one preview. Select fewer categories.')
    return dict(entries=sorted(all_entries, key=lambda e: e['path']), groups=groups,
                bytes=sum(item['bytes'] for item in groups), warnings=warnings[:50])


def state_root(system=False):
    if not system:
        return cleanup.roots()[1] / 'hyprshell'
    if os.geteuid() != 0:
        raise ValueError('Administrator cleanup requires desktop authentication.')
    uid = os.environ.get('PKEXEC_UID', '')
    if not uid.isdecimal() or int(uid) == 0:
        raise ValueError('Launch administrator cleanup from your desktop user account.')
    pwd.getpwuid(int(uid))
    # Separate root-owned state; never trust a plan stored in a user-writable folder.
    base = Path('/var/lib/hyprshell-system-cleanup')
    base.mkdir(mode=0o700, exist_ok=True)
    with_directory(base)
    info = base.stat()
    if info.st_uid != 0 or info.st_mode & 0o077:
        raise ValueError('Administrator cleanup state must be owned by root and private.')
    folder = base / uid
    folder.mkdir(mode=0o700, exist_ok=True)
    with_directory(folder)
    info = folder.stat()
    if info.st_uid != 0 or info.st_mode & 0o077:
        raise ValueError('Administrator cleanup state is unsafe.')
    return folder


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def plan_identity(value):
    # Tool-managed caches and live logs naturally change size between review and
    # apply. Their confirmed scope is the fixed command and policy, not file hashes.
    return dict(entries=value['entries'], groups=[
        {key: item.get(key) for key in ('id', 'paths', 'policy', 'blocked', 'command')}
        for item in value['groups']])


def matches(info, entry):
    return stat.S_ISREG(info.st_mode) and (
        info.st_ino, info.st_dev, info.st_size, info.st_uid, info.st_mtime_ns, info.st_ctime_ns
    ) == (entry['inode'], entry['device'], entry['size'], entry['uid'], entry['mtime'], entry['ctime'])


def verify_entries(entries):
    for entry in entries:
        path = Path(entry['path'])
        fd = cleanup.secure_parent(path)
        try:
            info = os.stat(path.name, dir_fd=fd, follow_symlinks=False)
            if not matches(info, entry):
                raise ValueError('A previewed file changed. Preview again before cleaning.')
        finally:
            os.close(fd)


def read_record(state, payload):
    path = state / 'system-cleanup-preview.json'
    with_directory(state)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 64_000_000:
        raise ValueError('Preview the selected cleanup again.')
    record = json.loads(path.read_text())
    supplied = payload.get('token')
    if (not isinstance(supplied, str) or not secrets.compare_digest(supplied, record['token'])
            or not 0 <= time.time() - record['created'] <= EXPIRY):
        raise ValueError('Cleanup preview expired. Preview again.')
    return record


def reset_request(payload):
    state = state_root()
    operation = payload['operation']
    if operation == 'reset-preview':
        before = recovery.current()
        record = dict(kind='reset', token=secrets.token_hex(24), created=time.time(),
                      revision=recovery.revision(), before=before)
        backend.atomic(state / 'system-cleanup-preview.json', json.dumps(record))
        changes = [key for key in backend.DEFAULTS if before[key] != backend.DEFAULTS[key]]
        return dict(ok=True, preview=dict(token=record['token'], changes=changes),
                    message='Reset saved Hyprshell preferences only. A recovery checkpoint is created first.')
    record = read_record(state, payload)
    if record.get('kind') != 'reset' or payload.get('confirmation') != 'RESET':
        raise ValueError('Preview the reset and type RESET to confirm.')
    if record['revision'] != recovery.revision():
        raise ValueError('Settings changed after preview. Preview again.')
    checkpoint = recovery.checkpoint(record['revision'])
    result = backend.save(copy.deepcopy(backend.DEFAULTS), expected=record['before'])
    (state / 'system-cleanup-preview.json').unlink(missing_ok=True)
    return dict(result, restored=copy.deepcopy(backend.DEFAULTS),
                message='Hyprshell settings reset. Undo checkpoint: ' + checkpoint + '. '
                'Restore it from Updates & recovery if needed.')


def request(payload, system=False):
    if not isinstance(payload, dict):
        raise ValueError('Invalid cleanup request.')
    operation = payload.get('operation')
    if operation == 'system-catalog' and not system:
        return dict(ok=True, groups=catalog(True), message='Select categories, then preview. Administrator access is requested only when you preview or clean.')
    if operation == 'catalog':
        return dict(ok=True, groups=catalog(system), message='Select categories, then preview. Nothing is selected by default.')
    if operation in ('reset-preview', 'reset'):
        if system:
            raise ValueError('Settings reset must run as your normal user.')
        return reset_request(payload)
    if operation not in ('preview', 'clean', 'files'):
        raise ValueError('Unknown cleanup operation.')
    state = state_root(system)
    with backend.lock(state / 'system-cleanup.lock'):
        if operation == 'files':
            record = read_record(state, payload)
            offset = payload.get('offset', 0)
            if record.get('kind') != 'cleanup' or type(offset) is not int or not 0 <= offset <= MAX_FILES:
                raise ValueError('Invalid file-list page. Preview again.')
            return dict(ok=True, filePage=dict(offset=offset, entries=record['plan']['entries'][offset:offset + 200]))
        if operation == 'preview':
            choice = options(payload, system)
            result = plan(choice, system)
            token = secrets.token_hex(24)
            record = dict(kind='cleanup', created=time.time(), token=token, choice=choice, plan=result)
            backend.atomic(state / 'system-cleanup-preview.json', json.dumps(record))
            list_path = ''
            if not system:
                list_path = str(state / 'system-cleanup-files.txt')
                backend.atomic(Path(list_path), '\n'.join(f"{e['size']} bytes\t{e['path']}" for e in result['entries']) + '\n')
            return dict(ok=True, preview=dict(result, entries=result['entries'][:200],
                totalFiles=len(result['entries']), token=token, listPath=list_path),
                message='Review the selected directories and impacts. Preview expires after five minutes.')
        if payload.get('confirmed') is not True:
            raise ValueError('Review and confirm cleanup before deleting files.')
        record = read_record(state, payload)
        if record.get('kind') != 'cleanup':
            raise ValueError('Preview this cleanup again.')
        current = plan(record['choice'], system)
        if digest(plan_identity(current)) != digest(plan_identity(record['plan'])):
            raise ValueError('Files, application activity or access changed. Preview again.')
        excluded = payload.get('excluded', [])
        if (not isinstance(excluded, list) or any(not isinstance(path, str) for path in excluded)
                or set(excluded) - {entry['path'] for entry in current['entries']}):
            raise ValueError('File selection changed. Preview again.')
        excluded = set(excluded)
        verify_entries(current['entries'])
        # Consume before changes, so retry after failure always needs a fresh preview.
        (state / 'system-cleanup-preview.json').unlink()
        removed, errors, actions = 0, [], []
        for entry in current['entries']:
            if entry['path'] in excluded:
                continue
            try:
                path = Path(entry['path']); fd = cleanup.secure_parent(path)
                try:
                    if not matches(os.stat(path.name, dir_fd=fd, follow_symlinks=False), entry):
                        raise ValueError('A previewed file changed; it was skipped: ' + str(path))
                    os.unlink(path.name, dir_fd=fd)
                finally:
                    os.close(fd)
                removed += 1
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
        for item in current['groups']:
            if item['policy'] == 'command' and not item['blocked']:
                try:
                    command = command_for(item['id'])
                    done = subprocess.run(command, capture_output=True, text=True, timeout=180)
                    actions.append(dict(title=item['title'], ok=done.returncode == 0,
                                        output=(done.stdout + done.stderr)[-4000:]))
                    if done.returncode:
                        errors.append(item['title'] + ': ' + (done.stderr or done.stdout)[-1000:])
                except (OSError, subprocess.SubprocessError) as exc:
                    errors.append(item['title'] + ': ' + str(exc))
        result = dict(ok=not errors, removed=removed, actions=actions, errors=errors[:30],
            message=f'Removed {removed} previewed files. Ran {len(actions)} maintenance actions. '
                    + ('Some operations failed; see details. Preview again before retrying.' if errors else
                       'Empty directories are retained. Unselected categories were preserved.'))
        backend.atomic(state / 'system-cleanup-last.json', json.dumps(dict(result, time=time.time())))
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--request-json', required=True)
    parser.add_argument('--system', action='store_true')
    args = parser.parse_args()
    try:
        if args.system and os.geteuid() != 0:
            raise ValueError('Administrator cleanup requires desktop authentication.')
        if not args.system and os.geteuid() == 0:
            raise ValueError('User cleanup and settings reset must run as your normal user.')
        result = request(json.loads(args.request_json), args.system)
    except (ValueError, OSError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        result = dict(ok=False, message=str(exc))
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
