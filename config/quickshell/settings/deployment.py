"""Stage and transactionally deploy owned files while preserving user preferences."""
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

PREFERENCES = {'settings.json', 'cleanup.json', 'keybindings.json', 'keybindings.lua',
               'displays.json', 'displays.lua', 'theme.json', 'applications.json',
               'regional.json', 'behavior.json', 'behavior.lua', 'overrides.lua'}


def roots():
    home = Path.home()
    return {'config': Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config'),
            'home': home, 'data': Path(os.environ.get('XDG_DATA_HOME') or home / '.local/share'),
            'state': Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'hyprshell'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def protected(key):
    return (key.startswith('config/hyprshell/hyprland/') or key == 'config/hypr/hyprland-gui.lua'
            or key.startswith('config/hyprshell/') and Path(key).name in PREFERENCES
            or key == 'config/xdg-terminals.list')


def ignored(path):
    return any(p in ('__pycache__', '.git') for p in path.parts) or path.suffix in ('.pyc', '.pyo') or path.name == 'audio-spectrum' or ('wallpapers' in path.parts and path.name != 'default.jpg')


def payload(repo):
    files = {}
    groups = [('config/systemd/user', 'config/systemd/user'), ('config/hypr', 'config/hypr'), ('config/quickshell', 'config/quickshell'),
              ('config/hyprshell', 'config/hyprshell'), ('config/xdg-desktop-portal', 'config/xdg-desktop-portal'),
              ('config/autostart', 'config/autostart'), ('bin', 'home/.local/bin'),
              ('assets/applications', 'data/applications'), ('assets/fonts', 'data/fonts/hyprshell'),
              ('assets/wallpapers', 'home/Pictures/Wallpapers')]
    for source, target in groups:
        for path in sorted((repo / source).rglob('*')):
            if path.is_file() and not ignored(path.relative_to(repo)):
                files[target + '/' + path.relative_to(repo / source).as_posix()] = path
    for source, target in [('config/xdg-terminals.list', 'config/xdg-terminals.list'),
                           ('compatibility.json', 'config/quickshell/settings/compatibility.json')]:
        if (repo / source).is_file():
            files[target] = repo / source
    return files


def destination(key, locations):
    root, relative = key.split('/', 1)
    if root not in ('config', 'home', 'data') or '..' in Path(relative).parts or Path(relative).is_absolute():
        raise ValueError('Invalid deployment path')
    return locations[root] / relative


def safe_target(path, root):
    if root.is_symlink():
        raise ValueError('Resolve the symbolic link at the installation root before updating: ' + str(root))
    current = path
    while current != root:
        if current.is_symlink():
            raise ValueError('Resolve the symbolic link before updating: ' + str(current))
        current = current.parent
        if current == current.parent and current != root:
            raise ValueError('Installation path is outside its root')


def load_manifest(locations):
    path = locations['state'] / 'deployed.json'
    return json.loads(path.read_text()) if path.exists() else {'format': 1, 'files': {}}


def legacy_digest(repo, source):
    # Bootstrap old installs from committed source, never blindly bless live edits.
    try:
        result = subprocess.run(['git', '-C', str(repo), 'show', 'HEAD:' + source.relative_to(repo).as_posix()],
                                capture_output=True, timeout=10)
        if result.returncode == 0:
            return hashlib.sha256(result.stdout).hexdigest()
    except (ValueError, OSError, subprocess.SubprocessError):
        pass
    return digest(source)


def inspect(repo, locations=None, base_repo=None):
    locations = locations or roots()
    old = load_manifest(locations)['files']
    files = payload(repo)
    baseline = payload(base_repo or repo)
    changes, conflicts, preserved = [], [], []
    for key, source in files.items():
        target = destination(key, locations)
        safe_target(target, locations[key.split('/')[0]])
        if target.exists() and protected(key):
            preserved.append(key)
            continue
        current, incoming = digest(target), digest(source)
        if current == incoming:
            continue
        expected = old.get(key, {}).get('hash')
        committed = legacy_digest(base_repo or repo, baseline[key]) if key in baseline else None
        if current is not None and current not in (expected, committed):
            conflicts.append(key)
        changes.append(key)
    removed = []
    for key, record in old.items():
        if (key not in files and not protected(key) and key != 'config/quickshell/helpers/audio-spectrum'
                and not (key.startswith('home/Pictures/Wallpapers/') and Path(key).name != 'default.jpg')):
            target = destination(key, locations)
            safe_target(target, locations[key.split('/')[0]])
            if target.exists():
                if digest(target) != record['hash']:
                    conflicts.append(key)
                else:
                    removed.append(key)
    return {'changes': changes, 'conflicts': conflicts, 'preserved': preserved, 'removed': removed}


@contextmanager
def lock(locations):
    locations['state'].mkdir(parents=True, exist_ok=True)
    with (locations['state'] / 'deployment.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Another installation or update is already running.') from error
        yield


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    try:
        temp.write_text(json.dumps(data, indent=2) + '\n')
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def validate_staged(stage, native=False):
    config = stage / 'config'
    env = dict(os.environ, HOME=str(stage / 'home'), XDG_CONFIG_HOME=str(config),
               XDG_STATE_HOME=str(stage / 'state'), XDG_DATA_HOME=str(stage / 'data'),
               PYTHONPYCACHEPREFIX=str(stage / 'pycache'))
    # Import only after the user has approved the candidate (preview never calls this).
    script = r'''
import json,sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import backend
root=Path(sys.argv[2])
p=root/'hyprshell/settings.json'
value=backend.validate(json.loads(p.read_text()))
p.write_text(json.dumps(value,indent=2)+'\n')
(root/'hyprshell/overrides.lua').write_text(backend.render_hypr(value['hyprland'],True,value['accessibility']))
for name in ('behavior','displays','keybindings','theme','applications','regional','cleanup'):
    p=root/'hyprshell'/ (name+'.json')
    if not p.exists(): continue
    module=__import__(name)
    data=json.loads(p.read_text())
    if name=='keybindings':
        if data.get('version')!=1: raise ValueError('Unsupported keybindings schema')
        value=module.validate(data['entries'])
    else: value=module.validate(data)
    if name in ('behavior','displays','keybindings'):
        p.with_suffix('.lua').write_text(module.render(value))
'''
    subprocess.run(['python3', '-c', script, str(config / 'quickshell/settings'), str(config)],
                   env=env, check=True, capture_output=True, text=True, timeout=30)
    subprocess.run(['python3', '-m', 'compileall', '-q', str(config / 'quickshell/settings')],
                   env=env, check=True, capture_output=True, text=True, timeout=30)
    if shutil.which('luac'):
        for source in list((config / 'hypr').glob('*.lua')) + list((config / 'hyprshell').rglob('*.lua')):
            subprocess.run(['luac', '-p', str(source)], check=True, capture_output=True, timeout=10)
    if native:
        verified = subprocess.run(['Hyprland', '--verify-config', '--config', str(config / 'hypr/hyprland.lua')],
                                  env=env, check=True, capture_output=True, text=True, timeout=30)
        # Some Hyprland versions print parse errors with a zero exit status.
        if 'config ok' not in verified.stdout.lower():
            raise RuntimeError('Staged Hyprland configuration did not pass validation: ' + verified.stdout[-2000:])
        runners = ['/usr/lib64/qt6/bin/qmltestrunner', '/usr/lib/qt6/bin/qmltestrunner']
        runner = next((p for p in runners if Path(p).is_file()), shutil.which('qmltestrunner-qt6'))
        if not runner:
            raise RuntimeError('Qt 6 validation tools are missing. Install them before updating.')
        env.update(QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
        subprocess.run([runner, '-input', str(config / 'quickshell/tests')], env=env,
                       check=True, capture_output=True, text=True, timeout=180)


def rollback(backup, locations=None):
    locations = locations or roots()
    journal = json.loads((backup / 'transaction.json').read_text())
    # Refuse to erase edits made since installation.
    for row in journal['files']:
        target = destination(row['key'], locations)
        safe_target(target, locations[row['key'].split('/')[0]])
        if digest(target) != row['after']:
            raise RuntimeError('Changed since this update; preserve or restore manually: ' + row['key'])
    restore(journal, backup, locations)


def restore(journal, backup, locations):
    for row in reversed(journal['files']):
        target = destination(row['key'], locations)
        previous = backup / row['key']
        if row['existed']:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(previous, target)
        elif target.exists():
            target.unlink()
    manifest = locations['state'] / 'deployed.json'
    if (backup / 'deployed.json').exists():
        shutil.copy2(backup / 'deployed.json', manifest)
    elif manifest.exists():
        manifest.unlink()


def install(repo, *, native=False, base_repo=None, locations=None):
    locations = locations or roots()
    repo = repo.resolve()
    with lock(locations):
        plan = inspect(repo, locations, base_repo)
        if plan['conflicts']:
            raise RuntimeError('Local edits conflict with this update: ' + ', '.join(plan['conflicts']))
        files = payload(repo)
        # Preserve additional user Lua sections as well as the shipped sections.
        extra = locations['config'] / 'hyprshell/hyprland'
        for source in extra.rglob('*'):
            if source.is_file() and not ignored(source):
                key = 'config/' + source.relative_to(locations['config']).as_posix()
                safe_target(source, locations['config'])
                files.setdefault(key, source)
        state = locations['state']
        live_before = {key: digest(destination(key, locations)) for key in files}
        for name in PREFERENCES:
            key = 'config/hyprshell/' + name
            live_before[key] = digest(destination(key, locations))
        with tempfile.TemporaryDirectory(prefix='hyprshell-stage-') as temp:
            stage = Path(temp)
            for key, source in files.items():
                live = destination(key, locations)
                if protected(key) and live.exists():
                    source = live
                target = stage / key
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            # Retain optional preferences absent from the repository.
            for name in PREFERENCES:
                key = 'config/hyprshell/' + name
                live = destination(key, locations)
                safe_target(live, locations['config'])
                if live.is_file() and not (stage / key).exists():
                    (stage / key).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(live, stage / key)
            helper = stage / 'config/quickshell/helpers/audio-spectrum'
            subprocess.run(['cc', '-O2', str(helper.with_suffix('.c')), '-o', str(helper),
                            '-lpulse-simple', '-lpulse', '-lfftw3', '-lm'], check=True,
                           capture_output=True, text=True, timeout=60)
            validate_staged(stage, native)
            staged = {key: stage / key for key in files}
            staged['config/quickshell/helpers/audio-spectrum'] = helper
            for name in PREFERENCES:
                key = 'config/hyprshell/' + name
                if (stage / key).is_file():
                    staged[key] = stage / key
            # Save reviewed fingerprints; a concurrent Settings edit must stop deployment.
            before = {key: live_before.get(key, digest(destination(key, locations))) for key in staged}
            if any(digest(destination(key, locations)) != before[key] for key in staged):
                raise RuntimeError('Settings changed during validation. Check again.')
            if inspect(repo, locations, base_repo)['conflicts']:
                raise RuntimeError('Local desktop code changed during validation. Check again.')
            changed = [key for key, source in staged.items() if before[key] != digest(source)]
            backup = state / 'backups' / ('update-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
            journal = {'format': 1, 'files': []}
            old_manifest = state / 'deployed.json'
            if changed or plan['removed']:
                backup.mkdir(parents=True)
                if old_manifest.exists():
                    shutil.copy2(old_manifest, backup / 'deployed.json')
                for key in changed + plan['removed']:
                    target = destination(key, locations)
                    safe_target(target, locations[key.split('/')[0]])
                    row = {'key': key, 'existed': target.exists(), 'after': digest(staged[key]) if key in staged else None}
                    journal['files'].append(row)
                    if target.exists():
                        saved = backup / key
                        saved.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(target, saved)
                atomic_json(backup / 'transaction.json', journal)
            applied = {'files': []}
            try:
                for key in changed:
                    target = destination(key, locations)
                    if digest(target) != before[key]:
                        raise RuntimeError('Settings changed during the update. Check again.')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    temporary = target.with_name('.' + target.name + '-' + uuid.uuid4().hex)
                    try:
                        shutil.copy2(staged[key], temporary)
                        os.replace(temporary, target)
                    finally:
                        if temporary.exists():
                            temporary.unlink()
                    applied['files'].append(next(row for row in journal['files'] if row['key'] == key))
                for key in plan['removed']:
                    destination(key, locations).unlink()
                    applied['files'].append(next(row for row in journal['files'] if row['key'] == key))
                atomic_json(old_manifest, {'format': 1, 'files': {key: {'hash': digest(source)} for key, source in staged.items()}})
            except BaseException:
                if applied['files']:
                    restore(applied, backup, locations)
                raise
            atomic_json(state / 'last-deployment.json', {'backup': str(backup) if backup.exists() else '',
                                                        'changed': changed, 'removed': plan['removed']})
            return {'changed': changed, 'preserved': plan['preserved'], 'backup': str(backup) if backup.exists() else ''}
