"""Build review trees and resolve file conflicts without committing local edits."""
import hashlib
import difflib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import deployment
from github_sync import PROJECT_PATHS, copy_exclusions, git, snapshot, file_hash


def allowed(name):
    return any(name == p or name.startswith(p + '/') for p in PROJECT_PATHS)


def working_files(repo):
    raw = subprocess.run(['git', '-C', str(repo), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                         capture_output=True, check=True, timeout=15).stdout
    return sorted({p.decode() for p in raw.split(b'\0') if p})


def checkout_fingerprint(repo):
    rows = []
    for name in working_files(repo):
        p = repo / name
        rows.append((name, file_hash(p), p.stat().st_mode if p.exists() else None))
    return hashlib.sha256(repr(rows).encode()).hexdigest()


def capture_checkout(repo, target):
    from github_update import archive
    archive(repo, 'HEAD', target)
    for name in working_files(repo):
        if not allowed(name): continue
        source, destination = repo / name, target / name
        deployment.safe_target(source, repo)
        if source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        elif destination.is_file():
            destination.unlink()


def effective_local(repo, target):
    """Combine checkout and live edits in memory; leave both original copies alone."""
    from github_update import archive
    capture_checkout(repo, target)
    with tempfile.TemporaryDirectory(prefix='hyprshell-live-review-') as temp:
        live, head = Path(temp) / 'live', Path(temp) / 'head'
        shutil.copytree(target, live, ignore=copy_exclusions)
        archive(repo, 'HEAD', head)
        snapshot(live, deployment.roots()['config'], Path.home())
        head_payload = deployment.payload(head)
        current, installed = deployment.payload(target), deployment.payload(live)
        conflicts = []
        for key in current.keys() | installed.keys():
            if key == 'config/quickshell/settings/compatibility.json': continue
            relative = (current.get(key) or installed[key]).relative_to(target if key in current else live)
            ours = current.get(key)
            theirs = installed.get(key)
            base = head_payload.get(key)
            a, b, c = file_hash(ours) if ours else None, file_hash(theirs) if theirs else None, file_hash(base) if base else None
            if a == b or b == c: continue
            if a != c:
                conflicts.append(str(relative))
                continue
            dest = target / relative
            if theirs is None:
                if dest.exists(): dest.unlink()
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(theirs, dest)
        if conflicts:
            raise ValueError('The checkout and live desktop differ in the same files: ' + ', '.join(conflicts) + '. Reconcile these copies before checking for updates.')


def files(root):
    return {p.relative_to(root).as_posix(): p for p in root.rglob('*') if p.is_file() and not deployment.ignored(p.relative_to(root))}


def version(path):
    if path is None: return None
    return path.read_bytes(), bool(path.stat().st_mode & 0o111)


def describe(path):
    if path is None: return '(File deleted)'
    data = path.read_bytes()
    if b'\0' in data: return f'(Binary file, {len(data)} bytes)'
    try: value = data.decode('utf-8')
    except UnicodeDecodeError: return f'(Binary file, {len(data)} bytes)'
    return value[:24000] + ('\n… Preview truncated.' if len(value) > 24000 else '')


def difference(left, right):
    def lines(path):
        if path is None: return ['(File deleted)\n']
        data = path.read_bytes()
        if b'\0' in data: raise ValueError('binary')
        return [line + '\n' for line in data.decode('utf-8').splitlines()]
    try:
        diff = ''.join(difflib.unified_diff(lines(left), lines(right),
                     fromfile='Your local version', tofile='Developer’s GitHub version'))
    except (UnicodeDecodeError, ValueError):
        diff = 'Binary file change; choose which entire file to keep.\n'
    if left is not None and right is not None and version(left)[1] != version(right)[1]:
        diff += 'Executable permission: local=' + str(version(left)[1]) + ', developer=' + str(version(right)[1]) + '\n'
    if not diff:
        diff = 'File encoding or line endings differ. Choose which entire file to keep.\n'
    return diff[:48000] + ('\n… Diff truncated.' if len(diff) > 48000 else '')


def merge_directories(base, local, incoming, output, choices, skipped=()):
    """Three-way merge, with explicit full-file choices for conflicting changes."""
    output.mkdir(parents=True, exist_ok=True)
    ancestors, ours, theirs = files(base), files(local), files(incoming)
    conflicts = []
    for name in sorted(ancestors.keys() | ours.keys() | theirs.keys()):
        if name in skipped: continue
        old, left, right = ancestors.get(name), ours.get(name), theirs.get(name)
        b, l, r = version(old), version(left), version(right)
        chosen = None
        content = None
        if l == r: chosen = left
        elif l == b: chosen = right
        elif r == b: chosen = left
        else:
            merged = None
            if all(v is not None for v in (b, l, r)) and not any(b'\0' in v[0] for v in (b, l, r)):
                result = subprocess.run(['git', 'merge-file', '-p', str(left), str(old), str(right)],
                                        capture_output=True, timeout=15)
                if result.returncode == 0 and (l[1] == r[1] or l[1] == b[1] or r[1] == b[1]):
                    merged = result.stdout
            if merged is not None:
                chosen, content = left, merged
            else:
                decision = choices.get(name)
                conflicts.append({'path': name, 'local': describe(left), 'github': describe(right),
                                  'diff': difference(left, right),
                                  'choice': decision or '', 'localDeleted': left is None, 'githubDeleted': right is None})
                chosen = right if decision == 'github' else left
        if chosen is not None:
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(chosen, target)
            if content is not None: target.write_bytes(content)
    return conflicts


def write_tree(repo, root):
    # An isolated index writes blobs/trees only; HEAD and the user's index stay intact.
    with tempfile.TemporaryDirectory(prefix='hyprshell-index-') as temp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temp) / 'index'))
        command = ['git', '--git-dir', git(repo, 'rev-parse', '--absolute-git-dir'), '--work-tree', str(root)]
        subprocess.run(command + ['read-tree', '--empty'], env=env, check=True, capture_output=True, timeout=15)
        subprocess.run(command + ['add', '-A', '--', '.'], env=env, check=True, capture_output=True, timeout=30)
        return subprocess.run(command + ['write-tree'], env=env, check=True, capture_output=True, text=True, timeout=15).stdout.strip()


# Generated preference files travel with their editable source. Core shell code
# is deliberately excluded from optional updates because its files depend on one another.
PREFERENCE_GROUPS = {
    'settings': ('Desktop appearance, panels and locking', ('settings.json', 'overrides.lua')),
    'theme': ('Application theme, fonts and cursor', ('theme.json',)),
    'keybindings': ('Keyboard shortcuts', ('keybindings.json', 'keybindings.lua')),
    'displays': ('Displays (hardware dependent)', ('displays.json', 'displays.lua')),
    'behavior': ('Window behavior', ('behavior.json', 'behavior.lua')),
    'applications': ('Default apps and startup', ('applications.json',)),
    'regional': ('Language and region', ('regional.json',)),
    'cleanup': ('Cleanup schedule', ('cleanup.json',)),
}
OPTIONAL_CONFIGS = ('config/kitty/', 'config/mpv/')


def selections(base, local, incoming, choices):
    """Return explicit preference groups and independent configuration choices."""
    ancestors, ours, theirs = files(base), files(local), files(incoming)
    names = ancestors.keys() | ours.keys() | theirs.keys()
    groups, grouped = [], set()
    for label, members in PREFERENCE_GROUPS.values():
        paths = ['config/hyprshell/' + name for name in members]
        groups.append((paths[0], label, paths, True))
        grouped.update(paths)
    for name in sorted(names - grouped):
        if deployment.protected(name):
            groups.append((name, 'Desktop configuration: ' + name, [name], True))
        elif (name.startswith(OPTIONAL_CONFIGS) or name == 'assets/wallpapers/default.jpg') and version(ancestors.get(name)) != version(theirs.get(name)):
            groups.append((name, name, [name], False))
    rows, policies = [], []
    for key, label, paths, preference in groups:
        paths = [name for name in paths if name in names]
        if not paths: continue
        default = 'local' if preference or any(version(ours.get(name)) != version(ancestors.get(name)) for name in paths) else 'github'
        decision = choices.get(key, default)
        policies.append((paths, decision))
        if not any(version(ours.get(name)) != version(theirs.get(name)) for name in paths):
            continue
        def preview(mapping):
            if len(paths) == 1: return describe(mapping.get(paths[0]))
            return '\n\n'.join(name + '\n' + describe(mapping.get(name)) for name in paths)
        rows.append({'path': key, 'label': label, 'files': paths, 'preference': preference,
                     'choice': decision, 'local': preview(ours), 'github': preview(theirs),
                     'diff': '\n'.join(name + '\n' + difference(ours.get(name), theirs.get(name))
                                       for name in paths if version(ours.get(name)) != version(theirs.get(name)))})
    return rows, policies


def apply_selections(output, local, incoming, policies):
    for paths, decision in policies:
        selected = local if decision == 'local' else incoming
        for name in paths:
            source, target = selected / name, output / name
            if source.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)


def build(repo, base, incoming, choices):
    from github_update import archive
    ancestor = git(repo, 'merge-base', base, incoming)
    with tempfile.TemporaryDirectory(prefix='hyprshell-combine-') as temp:
        root = Path(temp)
        for name, revision in (('ancestor', ancestor), ('committed', base), ('incoming', incoming)):
            archive(repo, revision, root / name)
        effective_local(repo, root / 'local')
        rows, policies = selections(root / 'ancestor', root / 'local', root / 'incoming', choices)
        skipped = {name for paths, _ in policies for name in paths}
        conflicts = merge_directories(root / 'ancestor', root / 'local', root / 'incoming', root / 'result', choices, skipped)
        committed_conflicts = merge_directories(root / 'ancestor', root / 'committed', root / 'incoming', root / 'history', choices, skipped)
        seen = {c['path'] for c in conflicts}
        conflicts.extend(c for c in committed_conflicts if c['path'] not in seen)
        unknown = set(choices) - {c['path'] for c in conflicts + rows}
        if unknown or any(v not in ('local', 'github') for v in choices.values()):
            raise ValueError('Invalid conflict choices. Review the update again.')
        apply_selections(root / 'result', root / 'local', root / 'incoming', policies)
        apply_selections(root / 'history', root / 'committed', root / 'incoming', policies)
        return {'tree': write_tree(repo, root / 'result'), 'history_tree': write_tree(repo, root / 'history'),
                'checkout_tree': capture_tree(repo),
                'conflicts': conflicts, 'selections': rows}


def capture_tree(repo):
    with tempfile.TemporaryDirectory(prefix='hyprshell-checkout-') as temp:
        capture_checkout(repo, Path(temp))
        return write_tree(repo, Path(temp))


def overlay(repo, before, after, verify=False):
    """Apply a known tree delta, leaving unrelated paths alone."""
    a, b = files(before), files(after)
    if verify:
        for name in a.keys() | b.keys():
            if version(a.get(name)) != version(b.get(name)) and version(repo / name if (repo / name).is_file() else None) != version(a.get(name)):
                raise ValueError('Your checkout changed during the update: ' + name)
    for name in sorted(a.keys() | b.keys(), key=lambda n: (n.count('/'), n), reverse=True):
        if version(a.get(name)) == version(b.get(name)): continue
        target = repo / name
        deployment.safe_target(target, repo)
        if name not in b:
            if target.is_file(): target.unlink()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(b[name], target)
