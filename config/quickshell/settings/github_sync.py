#!/usr/bin/env python3
"""Commit the approved live configuration when publishing, without rewriting history."""
import argparse
import fnmatch
import json
import hashlib
import tempfile
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

FORK_URL = 'https://github.com/orapagier/hyprshell/fork'


def git(repo, *args):
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never')
    env.setdefault('GIT_SSH_COMMAND', 'ssh -oBatchMode=yes -oConnectTimeout=15')
    result = subprocess.run(['git', '-C', str(repo), *args], capture_output=True,
                            text=True, env=env, timeout=120)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or 'Git command failed')
    return result.stdout.strip()


def excluded(name):
    return name in ('__pycache__', '.git', 'audio-spectrum', 'hyprmonitor', 'hyprweather', 'target') or any(
        fnmatch.fnmatch(name, pattern) for pattern in ('*.pyc', '*.pyo', '*.bak*', '*.log', '.DS_Store'))


def mirror(source, destination):
    if source.resolve() == destination.resolve():
        return
    if source.is_symlink():
        raise RuntimeError(f'Cannot sync symbolic link: {source}')
    if source.is_dir():
        if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
            raise RuntimeError(f'Conflicting destination: {destination}')
        destination.mkdir(parents=True, exist_ok=True)
        names = {p.name for p in source.iterdir() if not excluded(p.name)}
        for child in destination.iterdir():
            if child.name not in names and not excluded(child.name):
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        for name in sorted(names):
            mirror(source / name, destination / name)
    else:
        if not source.is_file() or destination.is_symlink():
            raise RuntimeError(f'Cannot sync file: {source}')
        shutil.copy2(source, destination)



def snapshot_managed_files(repo, config, home):
    """Capture installer-owned files without importing unrelated user files."""
    sections = config / 'hyprshell/hyprland'
    if sections.is_dir():
        mirror(sections, repo / 'config/hyprshell/hyprland')
    terminal = config / 'xdg-terminals.list'
    if terminal.is_file():
        (repo / 'config').mkdir(parents=True, exist_ok=True)
        mirror(terminal, repo / 'config/xdg-terminals.list')
    portal = config / 'xdg-desktop-portal'
    if portal.is_dir():
        # Other applications may own portal files; copy only our managed names.
        groups = [(repo / 'config/xdg-desktop-portal', portal)]
    else:
        groups = []
    groups.extend([
        (repo / 'config/kitty', config / 'kitty'),
        (repo / 'config/mpv', config / 'mpv'),
        (repo / 'config/autostart', config / 'autostart'),
        (repo / 'bin', home / '.local/bin'),
        (repo / 'assets/applications', home / '.local/share/applications'),
        (repo / 'assets/wallpapers', home / 'Pictures/Wallpapers'),
        (repo / 'config/systemd/user', config / 'systemd/user'),
        (repo / 'assets/fonts', home / '.local/share/fonts/hyprshell'),
    ])
    for destination, source in groups:
        if not destination.is_dir():
            continue
        for managed in sorted(destination.iterdir()):
            if managed.is_file() and not excluded(managed.name) and (destination.name != 'wallpapers' or managed.name == 'default.jpg'):
                live = source / managed.name
                if live.exists() or live.is_symlink():
                    mirror(live, managed)
    keybindings = config / 'hyprshell/keybindings.json'
    if keybindings.exists():
        from keybindings import validate as validate_keybindings, render as render_keybindings
        data = json.loads(keybindings.read_text())
        if data.get('version') != 1:
            raise ValueError('Unsupported keybindings version')
        entries = validate_keybindings(data['entries'])
        destination = repo / 'config/hyprshell'
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'keybindings.json').write_text(json.dumps({'version': 1, 'entries': entries}, indent=2) + '\n')
        (destination / 'keybindings.lua').write_text(render_keybindings(entries))
    behavior = config / 'hyprshell/behavior.json'
    if behavior.exists():
        from behavior import validate as validate_behavior, render as render_behavior
        data = validate_behavior(json.loads(behavior.read_text()))
        destination = repo / 'config/hyprshell'
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'behavior.json').write_text(json.dumps(data, indent=2) + '\n')
        (destination / 'behavior.lua').write_text(render_behavior(data))
    regional = config / 'hyprshell/regional.json'
    if regional.exists():
        from regional import validate as validate_regional
        data = validate_regional(json.loads(regional.read_text()))
        destination = repo / 'config/hyprshell/regional.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(data, indent=2) + '\n')
    applications = config / 'hyprshell/applications.json'
    if applications.exists():
        from applications import validate as validate_applications
        data = validate_applications(json.loads(applications.read_text()))
        destination = repo / 'config/hyprshell/applications.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(data, indent=2) + '\n')
    weather = config / 'hyprshell/weather.json'
    if weather.exists():
        from weather import validate as validate_weather
        data = validate_weather(json.loads(weather.read_text()))
        destination = repo / 'config/hyprshell/weather.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(data, indent=2) + '\n')
    theme = config / 'hyprshell/theme.json'
    if theme.exists():
        from theme import validate as validate_theme
        data = validate_theme(json.loads(theme.read_text()))
        destination = repo / 'config/hyprshell/theme.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(data, indent=2) + '\n')
    displays = config / 'hyprshell/displays.json'
    if displays.exists():
        from displays import validate as validate_displays, render as render_displays
        data = validate_displays(json.loads(displays.read_text()))
        destination = repo / 'config/hyprshell'
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'displays.json').write_text(json.dumps(data, indent=2) + '\n')
        (destination / 'displays.lua').write_text(render_displays(data))
    cleanup = config / 'hyprshell/cleanup.json'
    if cleanup.exists():
        from cleanup import validate as validate_cleanup
        data = validate_cleanup(json.loads(cleanup.read_text()))
        destination = repo / 'config/hyprshell/cleanup.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(data, indent=2) + '\n')


PROJECT_PATHS = ('config', 'bin', 'assets', 'apps', 'tools', 'tests', 'docs', '.github',
                 '.gitignore', 'README.md', 'setup.sh', 'packages.txt',
                 'packages-apps.txt', 'packages-fallback.txt', 'packages-fedora.txt',
                 'packages-apps-fedora.txt', 'compatibility.json', 'CHANGELOG.md')


def snapshot(repo, config, home):
    for name in ('hypr', 'quickshell'):
        if not (config / name).is_dir():
            raise RuntimeError(f'Missing live config: {config / name}')
        mirror(config / name, repo / 'config' / name)
    installed = repo / 'config/quickshell/settings/compatibility.json'
    if installed.exists():
        installed.unlink()
    import deployment
    for name in deployment.PREFERENCES:
        target = repo / 'config/hyprshell' / name
        if not (config / 'hyprshell' / name).exists() and target.is_file():
            target.unlink()
    settings = config / 'hyprshell/settings.json'
    if settings.exists():
        from backend import validate
        data = validate(json.loads(settings.read_text()))
        target = repo / 'config/hyprshell/settings.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, indent=2) + '\n')
    snapshot_managed_files(repo, config, home)
    overrides = config / 'hyprshell/overrides.lua'
    if overrides.is_file():
        mirror(overrides, repo / 'config/hyprshell/overrides.lua')


def copy_exclusions(directory, names):
    return [name for name in names if
            (excluded(name) and not (name == 'hyprmatrix' and (Path(directory) / name).is_dir())) or
            (Path(directory).name == 'wallpapers' and name != 'default.jpg')]


def validate_local_edits(changes):
    """Check edited source before applying repo edits to the running desktop."""
    for _, source, _ in changes:
        if source is None: continue
        if source.suffix == '.py':
            compile(source.read_bytes(), str(source), 'exec')
        elif source.suffix == '.lua' and shutil.which('luac'):
            subprocess.run(['luac', '-p', str(source)], check=True, capture_output=True, timeout=10)
        elif source.suffix == '.json' and source.parent.name == 'hyprshell':
            data = json.loads(source.read_text())
            if source.stem == 'settings':
                from backend import validate
                validate(data)
            elif source.stem in ('cleanup', 'displays', 'theme', 'applications', 'regional', 'behavior'):
                __import__(source.stem).validate(data)
            elif source.stem == 'keybindings':
                from keybindings import validate
                if data.get('version') != 1: raise ValueError('Unsupported keybindings schema')
                validate(data['entries'])


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def commit_message(repo):
    """Describe the staged snapshot without guessing intent or rewriting commits."""
    fields = git(repo, 'diff', '--cached', '--name-status', '--no-renames', '-z').split('\0')
    changes = list(zip(fields[0::2], fields[1::2]))
    components = set()
    for _, name in changes:
        path = Path(name)
        if name.startswith('config/hyprshell/hyprland/'):
            components.add('Hyprland ' + path.stem)
        elif name.startswith('config/hyprshell/'):
            components.add(path.stem + ' preferences')
        elif name.startswith('config/quickshell/settings/'):
            components.add(path.stem.replace('_', ' ') + ' settings')
        elif name.startswith('config/quickshell/'):
            components.add('desktop shell')
        elif name.startswith('config/hypr/'):
            components.add('Hyprland configuration')
        elif name.startswith('config/'):
            components.add(path.parts[1] + ' configuration')
        elif name.startswith('docs/') or name in ('README.md', 'CHANGELOG.md'):
            components.add('documentation')
        elif name.startswith('tests/'):
            components.add('tests')
        elif name.startswith('assets/wallpapers/'):
            components.add('wallpaper')
        elif name.startswith('assets/'):
            components.add('desktop assets')
        elif name.startswith('bin/'):
            components.add('desktop utilities')
        elif name.startswith('tools/') or name == 'setup.sh':
            components.add('setup tools')
        elif name.startswith('packages') or name == 'compatibility.json':
            components.add('package requirements')
        else:
            components.add(name)
    labels = sorted(components)
    subject = 'Update ' + ', '.join(labels)
    if len(subject) > 100:
        subject = f'Update {labels[0]} and {len(labels) - 1} other components' if len(labels) > 1 else 'Update Hyprshell configuration'
    actions = {'A': 'Add', 'M': 'Modify', 'D': 'Remove', 'T': 'Change type of'}
    body = '\n'.join(f'- {actions.get(status, "Update")} {json.dumps(name, ensure_ascii=False)}'
                     for status, name in changes)
    return subject + '\n\nCaptured local changes during Sync to GitHub:\n' + body


def save_local(repo, config, home=None):
    """Reconcile live/repo edits, then commit locally. Never contact GitHub."""
    from github_update import repository_lock
    import deployment
    home = home or Path.home()
    repo = repo.resolve()
    if Path(git(repo, 'rev-parse', '--show-toplevel')).resolve() != repo:
        raise RuntimeError('Choose the root of the Hyprshell Git checkout.')
    with repository_lock(repo), deployment.lock(deployment.roots()):
        if git(repo, 'diff', '--cached', '--name-only'):
            raise RuntimeError('Commit or unstage your staged changes before syncing.')
        baseline_path = deployment.roots()['state'] / 'local-config-baseline.json'
        saved = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
        baseline = saved.get('files', {}) if saved.get('repo') == str(repo) else {}
        with tempfile.TemporaryDirectory(prefix='hyprshell-local-') as directory:
            candidate = Path(directory)
            # Managed ancillary filenames come from the checkout, never private files.
            for name in ('config', 'bin', 'assets', 'apps'):
                if (repo / name).exists():
                    shutil.copytree(repo / name, candidate / name,
                                    ignore=copy_exclusions)
            snapshot(candidate, config, home)
            repo_payload = deployment.payload(repo)
            live_payload = deployment.payload(candidate)
            # The installed compatibility manifest is generated from the root manifest.
            pairs = {}
            for key in repo_payload.keys() | live_payload.keys():
                source = repo_payload.get(key) or repo / live_payload[key].relative_to(candidate)
                relative = source.relative_to(repo).as_posix()
                if relative == 'compatibility.json':
                    continue
                live = deployment.destination(key, dict(deployment.roots(), config=config, home=home,
                                                       data=home / '.local/share'))
                deployment.safe_target(live, config if key.startswith('config/') else home)
                pairs[relative] = (source, live_payload.get(key), live)
            changes = []
            conflicts = []
            for relative, (source, captured, live) in pairs.items():
                current = file_hash(source)
                incoming = file_hash(captured) if captured else None
                if current == incoming:
                    continue
                if relative in baseline:
                    previous = baseline[relative]
                else:
                    result = subprocess.run(['git', '-C', str(repo), 'show', 'HEAD:' + relative],
                                            capture_output=True, timeout=10)
                    previous = hashlib.sha256(result.stdout).hexdigest() if result.returncode == 0 else None
                if current != previous and incoming != previous:
                    conflicts.append(relative)
                elif incoming != previous:
                    changes.append((source, captured, file_hash(source)))
                else:
                    changes.append((live, source if source.exists() else None, file_hash(live)))
            if conflicts:
                raise RuntimeError('Repo and desktop both changed; resolve before saving: ' + ', '.join(conflicts))
            validate_local_edits(changes)
            # Plan all changes before writing, so a conflict never overwrites an edit.
            if any(file_hash(target) != expected for target, _, expected in changes):
                raise RuntimeError('Configuration changed during local saving. Try again.')
            for target, source, _ in changes:
                if source is None:
                    if target.exists(): target.unlink()
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
            tracked = git(repo, 'ls-files', '-z').split('\0')
            paths = [p for p in PROJECT_PATHS if (repo / p).exists() or any(
                n == p or n.startswith(p + '/') for n in tracked)]
            git(repo, 'add', '-A', '--', *paths)
            committed = bool(git(repo, 'diff', '--cached', '--name-only'))
            if committed:
                try:
                    git(repo, 'commit', '-m', commit_message(repo))
                except Exception:
                    git(repo, 'restore', '--staged', '--', *paths)
                    raise
            deployment.atomic_json(baseline_path, {'repo': str(repo), 'files': {
                relative: file_hash(source) for relative, (source, _, _) in pairs.items()}})
            return committed


def sync(repo, config, target=None, slug=None):
    """Explicitly save and commit the live configuration, then publish history."""
    from github_update import repository_lock
    repo = repo.resolve()
    if Path(git(repo, 'rev-parse', '--show-toplevel')).resolve() != repo:
        raise RuntimeError('Choose the root of the Hyprshell Git checkout.')
    # Save before network discovery: offline/failed publishing retains the commit.
    save_local(repo, config)
    with repository_lock(repo):
        branch = git(repo, 'symbolic-ref', '--quiet', '--short', 'HEAD')
        if target is None:
            account = discover()
            if not account['ready']:
                raise RuntimeError(account['message'])
            target, slug = account['target'], account['repository']
        pushed = git(repo, 'push', '--porcelain', target, f'HEAD:refs/heads/{branch}')
        if any(line.startswith('=\t') for line in pushed.splitlines()):
            return 'Nothing to sync now.'
    return f'Synced to {slug} ({branch}).'


def identity(repo, name, email):
    name, email = name.strip(), email.strip()
    if not name or len(name) > 200 or any(c in name for c in '\r\n<>'):
        raise ValueError('Enter your commit name or GitHub username.')
    if len(email) > 254 or '@' not in email or any(c.isspace() or c in '<>' for c in email):
        raise ValueError('Enter a valid commit email (your GitHub noreply email also works).')
    git(repo, 'config', '--local', 'user.name', name)
    git(repo, 'config', '--local', 'user.email', email)


def friendly_error(error):
    """Keep subprocess commands and diagnostics out of the settings UI."""
    detail = str(error)
    diagnostic = (getattr(error, 'stderr', None) or detail).lower()
    if isinstance(error, subprocess.TimeoutExpired) or 'timed out' in diagnostic:
        return 'GitHub took too long to respond. Check your internet connection and try again.'
    if any(term in diagnostic for term in ('could not resolve', 'no such host', 'network unavailable', 'network is unreachable', 'connection refused', 'connection reset', 'dial tcp', 'failed to connect')):
        return 'Could not reach GitHub. Check your internet connection and try again.'
    if any(term in diagnostic for term in ('http 401', 'authentication failed', 'not logged', 'bad credentials')):
        return 'GitHub sign-in needs to be renewed. Click Authenticate to sign in again.'
    if any(term in diagnostic for term in ('http 403', 'permission denied', 'access denied')):
        return 'GitHub denied access. Check your sign-in and repository permissions, then try again.'
    if any(term in diagnostic for term in ('non-fast-forward', 'fetch first', 'rejected')):
        return 'The GitHub repository has newer changes. Update your local repository before syncing again.'
    if isinstance(error, FileNotFoundError):
        return 'A required GitHub sync tool is missing. Check your Hyprshell installation and try again.'
    if isinstance(error, (OSError, subprocess.SubprocessError)) or any(term in diagnostic for term in ('command ', 'fatal:', 'error:', 'gh:', 'git ', 'github sync failed:')):
        return 'GitHub sync could not finish. Your local changes are still saved. Check your connection and sign-in, then try again.'
    return detail


def api(endpoint, missing_ok=False):
    result = subprocess.run(['gh', 'api', '--hostname', 'github.com', endpoint],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        if missing_ok and '(HTTP 404)' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or 'Could not contact GitHub. Authenticate and try again.')
    return json.loads(result.stdout)


def discover():
    if not shutil.which('gh'):
        return {'ok': True, 'ready': False, 'message': 'Click Authenticate to sign in to GitHub.'}
    user = api('user')
    login, user_id = user['login'], user['id']
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', login) or type(user_id) is not int:
        raise ValueError('GitHub returned an invalid account.')
    slug = login + '/hyprshell'
    result = {'ok': True, 'ready': False, 'login': login, 'repository': slug,
              'name': login, 'email': f'{user_id}+{login}@users.noreply.github.com'}
    repository = api('repos/' + slug, missing_ok=True)
    if repository is None:
        result.update(forkUrl=FORK_URL, createUrl=f'https://github.com/new?name=hyprshell&owner={login}',
                      message=f'{slug} was not found. Fork Hyprshell or create an empty repository named hyprshell in your account, then click Check again.')
    elif repository.get('full_name', '').lower() != slug.lower():
        result['message'] = f'{slug} was renamed. Fork or create a repository named hyprshell in your account, then check again.'
    elif not repository.get('permissions', {}).get('push') or repository.get('archived'):
        result['message'] = f'Your account cannot push to {slug}. Check repository permissions and authentication.'
    else:
        result.update(ready=True, target=f'https://github.com/{slug}.git',
                      message=f'Signed in as {login}. Ready to sync to {slug}.')
    return result


def login_terminal():
    import system_packages
    try:
        if not shutil.which('gh'):
            print('GitHub CLI is needed for browser authentication.')
            if input('Install GitHub CLI with the system package manager now? [y/N] ').lower() != 'y':
                return 1
            subprocess.run(system_packages.install_command(['github-cli']), check=True)
        subprocess.run(['gh', 'auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web'], check=True)
        subprocess.run(['gh', 'auth', 'setup-git', '--hostname', 'github.com'], check=True)
        print('Authenticated. Return to Hyprshell and click Sync.')
        input('Press Enter to close…')
        return 0
    except (OSError, subprocess.SubprocessError, EOFError) as error:
        print('Authentication failed:', error)
        try:
            input('Press Enter to close…')
        except EOFError:
            pass
        return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--status', action='store_true')
    parser.add_argument('--authenticate', action='store_true')
    parser.add_argument('--login-terminal', action='store_true')
    args = parser.parse_args()
    if args.login_terminal:
        return login_terminal()
    home = Path.home()
    state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'hyprshell'
    config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    try:
        pointer = state / 'repository'
        repo = Path(pointer.read_text().strip()) if pointer.exists() else home / 'repos/hyprshell'
        if args.status:
            result = discover()
        elif args.authenticate:
            terminal = subprocess.run(['kitty', '--wait', '--title', 'Hyprshell GitHub authentication',
                            sys.executable, str(Path(__file__).resolve()), '--login-terminal'],
                            capture_output=True, text=True, timeout=900)
            if terminal.returncode:
                raise RuntimeError(terminal.stderr.strip() or 'Could not complete the authentication window.')
            if not shutil.which('gh'):
                raise RuntimeError('Authentication was not completed. Click Authenticate and finish GitHub CLI setup.')
            status = subprocess.run(['gh', 'auth', 'status', '--hostname', 'github.com'],
                                    capture_output=True, text=True, timeout=20)
            if status.returncode:
                raise RuntimeError('GitHub sign-in was not completed. Click Authenticate to retry.')
            result = discover()
        else:
            result = {'ok': True, 'message': sync(repo, config)}
        print(json.dumps(result))
        return 0 if result['ok'] else 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'ok': False, 'message': friendly_error(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
