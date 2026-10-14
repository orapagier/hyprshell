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
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

import compatibility
import deployment
import update_merge
import system_packages
from github_sync import git, friendly_error

DEVELOPER_REPOSITORY = 'https://github.com/orapagier/hyprshell.git'
DEVELOPER_BRANCH = 'main'


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
    # Fetch by URL so a user's fork, tracking branch and push remote stay intact.
    checkout_branch = git(repo, 'symbolic-ref', '--quiet', '--short', 'HEAD')
    return {'remote': DEVELOPER_REPOSITORY, 'ref': 'refs/heads/' + DEVELOPER_BRANCH,
            'url': DEVELOPER_REPOSITORY, 'branch': DEVELOPER_BRANCH,
            'checkoutBranch': checkout_branch}


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
    for folder in ('hyprshell', 'hypr', 'quickshell'):
        for path in (locations['config'] / folder).rglob('*'):
            if path.is_file() and not deployment.ignored(path):
                files['config/' + path.relative_to(locations['config']).as_posix()] = path
    for key in files:
        path = deployment.destination(key, locations)
        deployment.safe_target(path, locations[key.split('/')[0]])
        result[key] = deployment.digest(path)
    return hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()


def preview(repo, choices=None, previous=None):
    with repository_lock(repo):
        selection = source(repo)
        base = git(repo, 'rev-parse', 'HEAD')
        if previous:
            review = reviewed(repo, previous, require_ready=False)
            target = review['target']
        else:
            git(repo, 'fetch', '--no-tags', '--no-recurse-submodules', selection['remote'], selection['ref'])
            target = git(repo, 'rev-parse', 'FETCH_HEAD^{commit}')
        blockers = []
        if git(repo, 'diff', '--cached', '--name-only'):
            blockers.append('Commit or unstage your staged changes before updating.')
        changed = subprocess.run(['git', '-C', str(repo), 'diff', '--name-only', '-z', 'HEAD'],
                                 capture_output=True, check=True, timeout=15).stdout
        untracked = subprocess.run(['git', '-C', str(repo), 'ls-files', '--others', '--exclude-standard', '-z'],
                                   capture_output=True, check=True, timeout=15).stdout
        if any(name and not update_merge.allowed(name.decode()) for name in (changed + untracked).split(b'\0')):
            blockers.append('Changes outside the desktop project must be saved or moved before updating.')
        forward = ancestor(repo, base, target)
        incoming = not ancestor(repo, target, base)
        combined = update_merge.build(repo, base, target, choices or {})
        tree = combined['tree']
        history_tree = combined['history_tree']
        merge_needed = incoming and (not forward or history_tree != git(repo, 'rev-parse', target + '^{tree}'))
        unresolved = [c for c in combined['conflicts'] if not c['choice']]
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
            missing = assessment['missingPackages']
            install_command = system_packages.install_command(missing, distro=info['distribution']) if missing and info['distribution'] in ('arch', 'fedora') else []
            platform_manifest = {**manifest, 'minimum': {}, 'required_major': {}, 'incompatible': {}}
            platform_ok = compatibility.assess(platform_manifest, info)['compatible']
            if merge_needed and not blockers:
                assessment['warnings'].append('This update will create a merge commit preserving your local commits and the incoming GitHub history.')
            plan = deployment.inspect(candidate, base_repo=repo)
            settings = deployment.roots()['config'] / 'hyprshell/settings.json'
            if settings.exists() and json.loads(settings.read_text()).get('version') != manifest['settings_schema']:
                blockers.append('Your settings schema requires a migration that this updater does not support.')
            can_install = bool(install_command) and incoming and not blockers and not unresolved and platform_ok
            blockers += assessment['blockers']
            commits = git(repo, 'log', '--max-count=80', '--format=%h %s', f'{base}..{target}').splitlines()
            changes = git(repo, 'diff', '--name-status', base, tree).splitlines()
            if any(any(name in row for name in ('setup.sh', 'config/boot/', 'config/sddm/', 'tools/install_boot',
                                                'tools/install_login', 'tools/configure_daily_driver')) for row in changes):
                assessment['warnings'].append('This update also changes system installation files. Sync updates your desktop; use full setup separately to apply boot, login or system-service changes.')
            notes = candidate / 'CHANGELOG.md'
            result = {'ok': True, 'ready': not blockers and not unresolved and incoming,
                      'message': 'No new updates from the developer’s GitHub repository.' if not incoming else ('Choose which version to keep for each conflict.' if unresolved else 'Review the developer’s updates and compatibility results before syncing.'),
                      'conflicts': combined['conflicts'],
                      'repository': selection['url'], 'branch': selection['branch'], 'base': base, 'target': target,
                      'commits': commits, 'changes': changes, 'notes': notes.read_text()[:12000] if notes.exists() else '',
                      'packagesAdded': sorted(set(wanted) - set(old)), 'packagesRemoved': sorted(set(old) - set(wanted)),
                      'missingPackages': missing, 'dependencyCommand': shlex.join(install_command),
                      'canInstallDependencies': can_install,
                      'dependencyFullUpgrade': info['distribution'] == 'arch',
                      'dependencyNote': ('Arch installs packages as part of a full system upgrade to avoid partial upgrades.'
                                         if info['distribution'] == 'arch' else
                                         'Fedora installs the missing requirements from your enabled repositories.'),
                      'checks': assessment['checks'], 'warnings': assessment['warnings'], 'blockers': blockers,
                      'acceptance': assessment['acceptance'], 'preserved': plan['preserved'],
                      'requiresAcknowledgment': bool(assessment['warnings'])}
        token = uuid.uuid4().hex
        result['token'] = token
        state = deployment.roots()['state']
        state.mkdir(parents=True, exist_ok=True)
        deployment.atomic_json(state / 'update-preview.json', {'created': time.time(), 'token': token,
            'repo': str(repo), 'source': selection, 'base': base, 'target': target, 'tree': tree, 'merge': merge_needed,
            'history_tree': history_tree, 'checkout_tree': combined['checkout_tree'],
            'checkout_fingerprint': update_merge.checkout_fingerprint(repo), 'choices': choices or {},
            'fingerprint': fingerprints(repo), 'machine': info, 'result': result})
        # Keep reviewed objects alive even if another fetch moves FETCH_HEAD.
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-update', target)
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-tree', tree)
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-history', history_tree)
        git(repo, 'update-ref', 'refs/hyprshell/reviewed-checkout', combined['checkout_tree'])
        return result


def reviewed(repo, token, require_ready=True):
    path = deployment.roots()['state'] / 'update-preview.json'
    if not path.exists():
        raise ValueError('Check for updates first.')
    review = json.loads(path.read_text())
    if (review['token'] != token or review['repo'] != str(repo) or
            time.time() - review['created'] > 3600 or require_ready and not review['result']['ready']):
        raise ValueError('This preview has expired or cannot be applied. Check for updates again.')
    if review.get('dependenciesRequested'):
        raise ValueError('Dependency installation was requested. Check again after the terminal finishes.')
    if (git(repo, 'rev-parse', 'HEAD') != review['base'] or
            update_merge.checkout_fingerprint(repo) != review['checkout_fingerprint'] or
            source(repo) != review['source'] or fingerprints(repo) != review['fingerprint']):
        raise ValueError('Your repository or desktop changed after the preview. Check for updates again.')
    return review


def install_dependencies(repo, token, acknowledged=False):
    if not acknowledged:
        raise ValueError('Review the missing dependencies and confirm installation first.')
    with repository_lock(repo):
        review = reviewed(repo, token, require_ready=False)
        if not review['result'].get('canInstallDependencies'):
            raise ValueError('Resolve the update review before installing dependencies.')
        info = compatibility.machine()
        if info != review['machine']:
            raise ValueError('Your system changed after the preview. Check again before installing dependencies.')
        # Read package names as data from the exact reviewed tree. Never run
        # installer code from an incoming revision to install its dependencies.
        with tempfile.TemporaryDirectory(prefix='hyprshell-dependencies-') as temp:
            candidate = Path(temp)
            archive(repo, review['tree'], candidate)
            package_file = 'packages-fedora.txt' if info['distribution'] == 'fedora' else 'packages.txt'
            wanted = compatibility.packages(candidate / package_file)
            missing = compatibility.missing_packages(wanted, info['distribution'])
        if missing != review['result']['missingPackages'] or not missing or not set(missing) <= set(wanted):
            raise ValueError('The missing dependencies changed. Check again to review the current requirements.')
        command = system_packages.install_command(missing, distro=info['distribution'])
        if not shutil.which('kitty') or not shutil.which(command[1]) or not shutil.which('sudo'):
            raise ValueError('Open a terminal and run: ' + shlex.join(command) + '. Then check for updates again.')
        # No shell, automatic yes, new repositories, or desktop deployment.
        # sudo and the package manager keep their normal interactive prompts.
        result = subprocess.run(['kitty', '--detach', '--hold', '--title', 'Hyprshell update dependencies', *command],
                                capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError('Could not open the installation terminal. Run: ' + shlex.join(command) + '. Then check again.')
        review['dependenciesRequested'] = True
        review['result']['ready'] = False
        deployment.atomic_json(deployment.roots()['state'] / 'update-preview.json', review)
    return {'ok': True, 'dependenciesStarted': True,
            'message': 'Installation terminal opened. Review the package transaction and authenticate there. When it finishes or is cancelled, choose Check again; the desktop update has not been applied.'}


def apply(repo, token):
    with repository_lock(repo):
        review = reviewed(repo, token)
        with tempfile.TemporaryDirectory(prefix='hyprshell-apply-') as temp:
            candidate = Path(temp) / 'candidate'
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
                               'commit-tree', review['history_tree'], '-p', review['base'], '-p', review['target'],
                               '-m', 'Merge reviewed Hyprshell update ' + review['target'][:12])
            # Keep unsaved edits outside committed history. The reviewed tree
            # applies to the desktop and becomes the checkout's unstaged content.
            history, original, head = Path(temp) / 'history', Path(temp) / 'original', Path(temp) / 'head'
            archive(repo, review['history_tree'], history)
            archive(repo, review['checkout_tree'], original)
            archive(repo, review['base'], head)
            build = {'channel': 'rolling', 'revision': revision, 'upstream_revision': review['target'],
                     'date': git(repo, 'show', '-s', '--format=%cs', review['target']),
                     'modified': review['tree'] != git(repo, 'rev-parse', review['target'] + '^{tree}')}
            installed = deployment.install(candidate, native=True, base_repo=repo, resolved=True, build=build)
            advanced = False
            checkout_touched = False
            try:
                if (git(repo, 'rev-parse', 'HEAD') != review['base'] or
                        update_merge.checkout_fingerprint(repo) != review['checkout_fingerprint'] or source(repo) != review['source']):
                    raise ValueError('Your checkout changed during validation. The desktop update will be rolled back; check again.')
                # Original uncommitted contents are backed by the reviewed tree.
                # Temporarily clear only captured project changes for the merge.
                checkout_touched = True
                update_merge.overlay(repo, original, head, verify=True)
                git(repo, '-c', 'core.hooksPath=/dev/null', 'merge', '--ff-only', revision)
                advanced = True
                update_merge.overlay(repo, history, candidate, verify=True)
            except BaseException:
                if advanced:
                    git(repo, 'update-ref', 'HEAD', review['base'], revision)
                    git(repo, 'read-tree', review['base'])
                    update_merge.overlay(repo, candidate, head)
                    update_merge.overlay(repo, history, head)
                if checkout_touched:
                    update_merge.overlay(repo, head, original)
                if installed['backup']:
                    deployment.rollback(Path(installed['backup']))
                raise
        deployment.atomic_json(deployment.roots()['state'] / 'installed-release.json',
                               {'revision': revision, 'upstream_revision': review['target'],
                                'source': review['source'], 'updated': time.time(), 'backup': installed['backup']})
        return {'ok': True, 'message': 'Hyprshell updated using your choices. Unsynced local edits remain uncommitted. Log out and back in to finish activation.',
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
    actions.add_argument('--resolve', metavar='TOKEN')
    actions.add_argument('--install-dependencies', metavar='TOKEN')
    parser.add_argument('--choices-json', default='{}')
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
        elif args.resolve:
            choices = json.loads(args.choices_json)
            if not isinstance(choices, dict): raise ValueError('Invalid conflict choices.')
            result = preview(repository(), choices, args.resolve)
        elif args.apply:
            result = start(repository(), args.apply, args.acknowledge)
        elif args.install_dependencies:
            result = install_dependencies(repository(), args.install_dependencies, args.acknowledge)
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
