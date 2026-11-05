#!/usr/bin/env python3
"""Install the four reviewed workload probes with a checkpoint and clean restart."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from capture_shell_baseline import assert_idle_media, restart, run, wait_until
from measure_shell import discover_pid, process_sample, tree_sample

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = {
    'shell.qml': '1f91585d5bc29f2fc1cf3673c25f3a6291c05af674cea378a2bb4e7121e77c63',
    'Hyprdock.qml': 'fb354f5e1cf9ce36f544181f400172b4a0234e575b5e2b0d25c8f8912d7fb18c',
    'FrameTiming.qml': 'ea337df22a6caf011313bb9c2cfc969677dd014839e62de6fcc9764c4f76108b',
    'WorkloadControl.qml': None,
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def validate(config):
    for name, original in ORIGINAL.items():
        source, target = ROOT / 'config/quickshell' / name, config / name
        if target.is_symlink() or not source.is_file():
            raise RuntimeError(f'Unsupported probe path: {name}')
        if digest(target) not in (original, digest(source)):
            raise RuntimeError(f'{target} has other edits; refusing to overwrite them')


def recover(config, helper, backup):
    def restore_files():
        run('python3', str(helper), 'restore', str(backup), '--apply')
    try:
        pid = discover_pid()
        current = {'root': dict(process_sample(pid), pid=pid), 'tree': tree_sample(pid)}
    except (ValueError, FileNotFoundError):
        current = None
    if current:
        if current['tree']['errors']:
            raise RuntimeError('Cannot inspect replacement shell for rollback; checkpoint retained')
        restart(config, current, before_start=restore_files)
    else:
        restore_files()
        run('quickshell', '--no-duplicate', '--daemonize', '--path', str(config))
        def ready():
            try:
                return run('quickshell', 'ipc', '--path', str(config), 'call', 'bar', 'ready') == 'true'
            except subprocess.SubprocessError:
                return False
        wait_until(ready, 'Original files restored but desktop readiness could not be verified')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', required=True)
    parser.parse_args()
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'quickshell'
    validate(config)
    assert_idle_media()
    if run('quickshell', 'ipc', '--path', str(config), 'call', 'bar', 'ready') != 'true':
        raise RuntimeError('Desktop is not ready')
    pid = discover_pid()
    initial = {'root': dict(process_sample(pid), pid=pid), 'tree': tree_sample(pid)}
    if initial['tree']['errors']:
        raise RuntimeError('Could not record existing helper tree')
    skill = Path.home() / '.agents/skills/hyprskill/scripts'
    helper = skill / 'checkpoint.py'
    backup = Path(run('python3', str(helper), 'create', '--label', 'Deploy workload instrumentation', '--',
                      *(str(config / name) for name in ORIGINAL)))
    (backup / 'runtime-before.json').write_text(json.dumps(initial, indent=2))
    (backup / 'notes.md').write_text('Workload probes only. No preference changes. Previous process tree in runtime-before.json.\n'
        + f'File rollback: python3 {helper} restore {backup} --apply\n'
        + 'After file rollback, a clean shell restart is required. Do not roll back while a capture is running.\n')
    print('Desktop checkpoint:', backup, flush=True)

    deployed = False
    def deploy():
        nonlocal deployed
        validate(config)
        try:
            for name in ORIGINAL:
                (config / name).write_bytes((ROOT / 'config/quickshell' / name).read_bytes())
            run('python3', str(helper), 'record-after', str(backup))
            deployed = True
        except Exception:
            run('python3', str(helper), 'record-after', str(backup))
            run('python3', str(helper), 'restore', str(backup), '--apply')
            raise

    try:
        restart(config, initial, before_start=deploy)
        result = json.loads(run('quickshell', 'ipc', '--path', str(config), 'call', 'performance', 'workloadState'))
        if result.get('version') != 1 or not result.get('supported'):
            raise RuntimeError('Workload probes loaded, but this scenario is unsupported')
        if any(r.get('name') == 'hypridle' for r in initial['tree']['processes'].values()):
            wait_until(lambda: any(r.get('name') == 'hypridle'
                                   for r in tree_sample(discover_pid())['processes'].values()),
                       'Idle helper did not return after probe installation')
    except Exception:
        if deployed:
            recover(config, helper, backup)
            print('Original files restored and desktop restarted; no workload was run.', flush=True)
        raise
    print('Probes ready. Close menus, keep media paused, and run:', flush=True)
    print('python3 tools/run_shell_workload.py', flush=True)
    with (backup / 'notes.md').open('a') as notes:
        notes.write('After successful live workload validation, advance matching sync paths:\npython3 '
                    + str(skill / 'sync_baseline.py') + ' --repo ' + str(ROOT) + ' --apply -- '
                    + ' '.join('config/quickshell/' + name for name in ORIGINAL) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit('Probe installation stopped: ' + str(error))
