#!/usr/bin/env python3
"""Review immutable GitHub updates, then deploy the exact reviewed revision."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

import compatibility
import deployment
from github_sync import git, friendly_error


def repository():
    pointer = deployment.roots()['state'] / 'repository'
    repo = Path(pointer.read_text().strip()) if pointer.exists() else Path.home() / 'repos/hyprshell'
    if Path(git(repo, 'rev-parse', '--show-toplevel')).resolve() != repo.resolve():
        raise ValueError('The saved Hyprshell repository is not a Git checkout root.')
    return repo.resolve()


@contextmanager
def repository_lock(repo):
    directory = Path(git(repo, 'rev-parse', '--absolute-git-dir'))
    with (directory / 'hyprshell-sync.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Another GitHub sync is already running.') from error
        if any((directory / name).exists() for name in ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'rebase-merge', 'rebase-apply')):
            raise ValueError('Finish the current merge or rebase before checking for updates.')
        yield


def source(repo):
    branch = git(repo, 'symbolic-ref', '--quiet', '--short', 'HEAD')
    remote = git(repo, 'config', '--get', f'branch.{branch}.remote') if has_config(repo, f'branch.{branch}.remote') else 'origin'
    ref = git(repo, 'config', '--get', f'branch.{branch}.merge') if has_config(repo, f'branch.{branch}.merge') else f'refs/heads/{branch}'
    if remote == '.' or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', remote) or not ref.startswith('refs/heads/'):
        raise ValueError('Configure a GitHub tracking branch for this checkout before updating.')
    url = git(repo, 'remote', 'get-url', remote)
    if not re.fullmatch(r'(?:https://github\.com/|git@github\.com:)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?', url):
        raise ValueError('The update remote must be an HTTPS or SSH GitHub repository.')
    return {'remote': remote, 'ref': ref, 'url': url, 'branch': branch}


def has_config(repo, key):
    result = subprocess.run(['git', '-C', str(repo), 'config', '--get', key], capture_output=True, timeout=10)
    return result.returncode == 0


def archive(repo, revision, target):
    result = subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar', revision],
                            capture_output=True, check=True, timeout=60)
    # Reject links, devices, absolute paths and traversal before extraction.
    with tarfile.open(fileobj=io.BytesIO(result.stdout)) as bundle:
        members = bundle.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isdir() or member.isfile()):
                raise ValueError('The update archive contains unsupported file types or paths.')
        bundle.extractall(target, members=members, filter='data')


def ancestor(repo, older, newer):
    result = subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', older, newer], capture_output=True, timeout=15)
    return result.returncode == 0


def fingerprints(repo):
    locations = deployment.roots()
    result = {}
    files = deployment.payload(repo)
    # Include optional preferences and local Lua so preview becomes stale on edits.
    for folder in ('hyprshell', 'hypr'):
        for path in (locations['config'] / folder).rglob('*'):
            if path.is_file() and not deployment.ignored(path):
                files['config/' + path.relative_to(locations['config']).as_posix()] = path
    for key in files:
        path = deployment.destination(key, locations)
        deployment.safe_target(path, locations[key.split('/')[0]])
        result[key] = deployment.digest(path)
    return hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()


def preview(repo):
    with repository_lock(repo):
        selection = source(repo)
        base = git(repo, 'rev-parse', 'HEAD')
        # Fetch only the selected branch. No checkout changes and no candidate code execution.
        git(repo, 'fetch', '--no-tags', '--no-recurse-submodules', selection['remote'], selection['ref'])
        target = git(repo, 'rev-parse', 'FETCH_HEAD^{commit}')
        blockers = []
        if git(repo, 'status', '--porcelain'):
            blockers.append('The checkout has uncommitted changes. Commit or save them before updating.')
        forward = ancestor(repo, base, target)
        incoming = not ancestor(repo, target, base)
        tree = target if incoming else base
        merge_needed = incoming and not forward
        if merge_needed:
            # Compute the combined tree without touching the index/worktree or
            # running candidate code. Both original histories stay intact.
            merged = subprocess.run(['git', '-C', str(repo), 'merge-tree', '--write-tree', base, target],
                                    capture_output=True, text=True, timeout=60)
            if merged.returncode:
                blockers.append('Local and GitHub edits have merge conflicts. Resolve them in Git before syncing.')
            else:
                tree = merged.stdout.splitlines()[0]
        with tempfile.TemporaryDirectory(prefix='hyprshell-review-') as temp:
            candidate = Path(temp)
            archive(repo, tree, candidate)
            manifest_path = candidate / 'compatibility.json'
            if not manifest_path.is_file():
                raise ValueError('This revision predates reviewed updates. Use a release with compatibility.json.')
            manifest = json.loads(manifest_path.read_text())
            info = compatibility.machine()
            package_file = 'packages-fedora.txt' if info['distribution'] == 'fedora' else 'packages.txt'
            wanted = compatibility.packages(candidate / package_file)
            old = compatibility.packages(repo / package_file)
            assessment = compatibility.assess(manifest, info, wanted)
            if merge_needed and not blockers:
                assessment['warnings'].append('This update will create a merge commit preserving your local commits and the incoming GitHub history.')
            plan = deployment.inspect(candidate, base_repo=repo)
            settings = deployment.roots()['config'] / 'hyprshell/settings.json'
            if settings.exists() and json.loads(settings.read_text()).get('version') != manifest['settings_schema']:
                blockers.append('Your settings schema requires a migration that this updater does not support.')
            if plan['conflicts']:
                blockers.append('Local desktop code has conflicting edits: ' + ', '.join(plan['conflicts']))
            blockers += assessment['blockers']
            commits = git(repo, 'log', '--max-count=80', '--format=%h %s', f'{base}..{target}').splitlines()
            changes = git(repo, 'diff', '--name-status', base, tree).splitlines()
            if any(any(name in row for name in ('setup.sh', 'config/boot/', 'config/sddm/', 'tools/install_boot',
                                                'tools/install_login', 'tools/configure_daily_driver')) for row in changes):
                assessment['warnings'].append('This update also changes system installation files. Sync updates your desktop; use full setup separately to apply boot, login or system-service changes.')
            notes = candidate / 'CHANGELOG.md'
            result = {'ok': True, 'ready': not blockers and incoming,
                      'message': 'No incoming updates.' if not incoming else 'Review the changes and compatibility results before syncing.',
                      'repository': selection['url'], 'branch': selection['branch'], 'base': base, 'target': target,
                      'commits': commits, 'changes': changes, 'notes': notes.read_text()[:12000] if notes.exists() else '',
                      'packagesAdded': sorted(set(wanted) - set(old)), 'packagesRemoved': sorted(set(old) - set(wanted)),
                      'checks': assessment['checks'], 'warnings': assessment['warnings'], 'blockers': blockers,
                      'acceptance': assessment['acceptance'], 'preserved': plan['preserved'],
                      'requiresAcknowledgment': bool(assessment['warnings'])}
        token = uuid.uuid4().hex
        result['token'] = token
        state = deployment.roots()['state']
        state.mkdir(parents=True, exist_ok=True)
        deployment.atomic_json(state / 'update-preview.json', {'created': time.time(), 'token': token,
            'repo': str(repo), 'source': selection, 'base': base, 'target': target, 'tree': tree, 'merge': merge_needed,
            'fingerprint': fingerprints(repo), 'machine': info, 'result': result})
        # Keep reviewed objects alive even if another fetch moves FETCH_HEAD.
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-update', target)
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-tree', tree)
        return result


def reviewed(repo, token):
    path = deployment.roots()['state'] / 'update-preview.json'
    if not path.exists():
        raise ValueError('Check for updates first.')
    review = json.loads(path.read_text())
    if (review['token'] != token or review['repo'] != str(repo) or
            time.time() - review['created'] > 3600 or not review['result']['ready']):
        raise ValueError('This preview has expired or cannot be applied. Check for updates again.')
    if (git(repo, 'rev-parse', 'HEAD') != review['base'] or git(repo, 'status', '--porcelain') or
            source(repo) != review['source'] or fingerprints(repo) != review['fingerprint']):
        raise ValueError('Your repository or desktop changed after the preview. Check for updates again.')
    return review


def apply(repo, token):
    with repository_lock(repo):
        review = reviewed(repo, token)
        with tempfile.TemporaryDirectory(prefix='hyprshell-apply-') as temp:
            candidate = Path(temp)
            archive(repo, review['tree'], candidate)
            info = compatibility.machine()
            if info != review['machine']:
                raise ValueError('Your software versions or detected hardware changed after preview. Check again.')
            package_file = 'packages-fedora.txt' if info['distribution'] == 'fedora' else 'packages.txt'
            result = compatibility.assess(json.loads((candidate / 'compatibility.json').read_text()), info,
                                          compatibility.packages(candidate / package_file))
            if not result['compatible']:
                raise ValueError('Compatibility changed since preview: ' + '; '.join(result['blockers']))
            revision = review['target']
            if review['merge']:
                revision = git(repo, '-c', 'user.name=Hyprshell updater', '-c', 'user.email=hyprshell@localhost',
                               'commit-tree', review['tree'], '-p', review['base'], '-p', review['target'],
                               '-m', 'Merge reviewed Hyprshell update ' + review['target'][:12])
            installed = deployment.install(candidate, native=True, base_repo=repo)
            try:
                if (git(repo, 'rev-parse', 'HEAD') != review['base'] or
                        git(repo, 'status', '--porcelain') or source(repo) != review['source']):
                    raise ValueError('Your checkout changed during validation. The desktop update will be rolled back; check again.')
                # Fast-forward to the reviewed SHA only; no reset, stash or rewritten commits.
                git(repo, '-c', 'core.hooksPath=/dev/null', 'merge', '--ff-only', revision)
            except BaseException:
                if installed['backup']:
                    deployment.rollback(Path(installed['backup']))
                raise
        deployment.atomic_json(deployment.roots()['state'] / 'installed-release.json',
                               {'revision': revision, 'source': review['source'], 'updated': time.time()})
        return {'ok': True, 'message': 'Hyprshell updated. Your preferences were retained. Log out and back in to finish activation.',
                'backup': installed['backup'], 'revision': revision}


def start(repo, token, acknowledged):
    with repository_lock(repo):
        reviewed(repo, token)
    if not acknowledged:
        raise ValueError('Review and acknowledge the compatibility limitations before syncing.')
    state = deployment.roots()['state']
    # A detached copy survives Quickshell hot reload and replacement of its own modules.
    worker = state / 'update-worker'
    job_lock = state / 'update-job.lock'
    with job_lock.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('An update is already running.') from error
        if worker.exists():
            shutil.rmtree(worker)
        shutil.copytree(Path(__file__).parent, worker, ignore=shutil.ignore_patterns('__pycache__'))
        deployment.atomic_json(state / 'update-status.json', {'ok': True, 'running': True,
                               'message': 'Validating and applying the reviewed update…'})
        fd = lock.fileno()
        with (state / 'update-worker.log').open('w') as log:
            subprocess.Popen([sys.executable, str(worker / 'github_update.py'), '--worker', token,
                              '--lock-fd', str(fd)], start_new_session=True, pass_fds=(fd,),
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log)
    return {'ok': True, 'running': True, 'message': 'Validating and applying the reviewed update…'}


def status():
    state = deployment.roots()['state']
    path = state / 'update-status.json'
    result = json.loads(path.read_text()) if path.exists() else {'ok': True, 'running': False, 'message': ''}
    if result.get('running'):
        with (state / 'update-job.lock').open('a') as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = {'ok': False, 'running': False, 'message': 'The update was interrupted. Inspect the local update log and backup before retrying.'}
            except BlockingIOError:
                pass
    return result


def main():
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--preview', action='store_true')
    actions.add_argument('--apply', metavar='TOKEN')
    actions.add_argument('--status', action='store_true')
    actions.add_argument('--worker', metavar='TOKEN')
    parser.add_argument('--acknowledge', action='store_true')
    parser.add_argument('--lock-fd', type=int)
    args = parser.parse_args()
    try:
        if args.status:
            result = status()
        elif args.preview:
            result = preview(repository())
        elif args.apply:
            result = start(repository(), args.apply, args.acknowledge)
        else:
            result = apply(repository(), args.worker)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            message = 'Update validation failed; see the local update-worker.log. Your previous desktop files were retained or restored.'
            if args.worker:
                print((error.stderr or error.stdout or str(error)), file=sys.stderr)
        else:
            message = friendly_error(error) if isinstance(error, (OSError, subprocess.SubprocessError)) else str(error)
        result = {'ok': False, 'message': message}
    if args.worker:
        result['running'] = False
        deployment.atomic_json(deployment.roots()['state'] / 'update-status.json', result)
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
