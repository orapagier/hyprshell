#!/usr/bin/env python3
"""Explicitly restart the desktop shell and capture three idle baselines locally."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from measure_shell import discover_pid, process_sample, tree_sample


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=15).stdout.strip()


def alive(pid, start):
    try:
        return (process_sample(pid)['start'] == start
                and (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()[0] != 'Z')
    except FileNotFoundError:
        return False


def wait_until(predicate, message, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.2)
    raise RuntimeError(message)


def assert_idle_media():
    result = subprocess.run(['playerctl', '-a', 'status'], capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        if 'No players found' in result.stderr:
            return
        raise RuntimeError('Media state unavailable: ' + result.stderr.strip())
    if 'Playing' in result.stdout.splitlines():
        raise RuntimeError('Pause media playback before capturing the idle baseline')


def stop_owned_idle(config, initial):
    """Recover only recorded descendants using this config, with PID-reuse protection."""
    root = initial['root']
    rows = {r['pid']: r for r in initial['tree']['processes'].values()}
    for row in rows.values():
        pid = row['pid']
        if pid == root['pid'] or row.get('name') != 'hypridle' or not alive(pid, row['start']):
            continue
        # The saved ownership chain must reach the old shell, not another service.
        parent, seen = row.get('ppid'), {pid}
        while parent != root['pid'] and parent in rows and parent not in seen:
            seen.add(parent)
            parent = rows[parent].get('ppid')
        if parent != root['pid']:
            raise RuntimeError(f'Cannot establish saved shell ownership of hypridle {pid}')
        if alive(root['pid'], root['start']):
            raise RuntimeError('Recorded shell is still running; refusing orphan recovery')
        # Acquire a stable kernel handle before validating identity or sending a signal.
        try:
            handle = os.pidfd_open(pid)
        except ProcessLookupError:
            continue
        try:
            if not alive(pid, row['start']):
                continue
            path = Path('/proc') / str(pid)
            args = (path / 'cmdline').read_bytes().split(b'\0')
            args = [os.fsdecode(value) for value in args if value]
            expected = str(config.parent / 'hyprshell/hypridle.conf')
            if (path.stat().st_uid != os.getuid() or not args or
                    Path(args[0]).name != 'hypridle' or args[1:] != ['-c', expected]):
                raise RuntimeError(f'hypridle {pid} does not match this Hyprshell config; left running')
            print(f'Stopping recorded Hyprshell idle helper {pid}.', flush=True)
            signal.pidfd_send_signal(handle, signal.SIGTERM)
        except ProcessLookupError:
            pass
        finally:
            os.close(handle)
        wait_until(lambda: not alive(pid, row['start']), f'Owned idle helper {pid} did not exit', seconds=5)


def restart(config, initial, recovery=None, before_start=None):
    root = initial['root']
    run('quickshell', 'kill', '--pid', str(root['pid']))
    wait_until(lambda: not alive(root['pid'], root['start']),
               'Old shell did not exit; no replacement was started')
    cleanup_error = None
    try:
        if recovery:
            stop_owned_idle(config, recovery)
        stop_owned_idle(config, initial)
        survivors = [r['pid'] for state in (initial, recovery) if state
                     for r in state['tree']['processes'].values()
                     if r['pid'] != state['root']['pid'] and alive(r['pid'], r['start'])]
        if survivors:
            raise RuntimeError(f'Old helpers remain: {survivors}; no unrelated processes were stopped')
        if before_start:
            before_start()
    except (OSError, RuntimeError) as error:
        cleanup_error = error
    finally:
        # Restore the desktop even if a helper cannot be cleaned up. Never collect
        # a baseline in that case; readiness alone does not establish idle health.
        run('quickshell', '--no-duplicate', '--daemonize', '--path', str(config))

    def ready():
        try:
            return run('quickshell', 'ipc', '--path', str(config), 'call', 'bar', 'ready') == 'true'
        except subprocess.SubprocessError:
            return False

    wait_until(ready, 'Shell started but did not become ready; inspect it before retrying')
    if cleanup_error:
        raise RuntimeError(f'Desktop restarted, but capture stopped: {cleanup_error}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restart', action='store_true', required=True,
                        help='Required acknowledgement: briefly restart the desktop shell')
    parser.add_argument('--recover-from', type=Path,
                        help='Prior before-restart.json identifying this task\'s surviving helpers')
    args = parser.parse_args()
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'quickshell'
    recovery = json.loads(args.recover_from.read_text()) if args.recover_from else None
    if recovery:
        # Validate the required schema before stopping anything.
        for row in [recovery['root'], *recovery['tree']['processes'].values()]:
            if not isinstance(row['pid'], int) or not isinstance(row['start'], int):
                raise ValueError('Invalid recovery process identity')
        if alive(recovery['root']['pid'], recovery['root']['start']):
            raise RuntimeError('Recovery record belongs to a still-running shell')
    assert_idle_media()
    monitors = json.loads(run('hyprctl', '-j', 'monitors'))
    if run('quickshell', 'ipc', '--path', str(config), 'call', 'bar', 'ready') != 'true':
        raise RuntimeError('Desktop is not ready; nothing was restarted')
    pid = discover_pid()
    initial = {'root': dict(process_sample(pid), pid=pid), 'tree': tree_sample(pid),
               'monitors': [{k: m[k] for k in ('name', 'width', 'height', 'refreshRate', 'scale')}
                            for m in monitors],
               'recovery_command': ['quickshell', '--no-duplicate', '--daemonize', '--path', str(config)]}
    if initial['tree']['errors']:
        raise RuntimeError('Cannot record existing process tree; nothing was restarted')
    directory = Path(tempfile.mkdtemp(prefix='hyprshell-fresh-', dir='/tmp'))
    (directory / 'before-restart.json').write_text(json.dumps(initial, indent=2))
    if recovery:
        (directory / 'recovery-source.json').write_text(json.dumps(recovery, indent=2))
    print('Capture directory:', directory, flush=True)
    print('Restarting only the selected shell; applications remain open.', flush=True)
    restart(config, initial, recovery)
    if any(r.get('name') == 'hypridle' for state in (initial, recovery) if state
           for r in state['tree']['processes'].values()):
        wait_until(lambda: any(r.get('name') == 'hypridle'
                               for r in tree_sample(discover_pid())['processes'].values()),
                   'Shell is ready but its idle helper did not restart; capture stopped')
    (directory / 'after-restart.json').write_text(json.dumps(tree_sample(discover_pid()), indent=2))
    print('Shell ready. Settling for 30 seconds; keep menus closed and media paused.', flush=True)
    time.sleep(30)
    fresh_pid = discover_pid()
    fresh_start = process_sample(fresh_pid)['start']
    if (fresh_pid, fresh_start) == (pid, initial['root']['start']):
        raise RuntimeError('Expected a new shell process; capture stopped')
    for index in range(1, 4):
        assert_idle_media()
        if not alive(fresh_pid, fresh_start):
            raise RuntimeError('Shell restarted between captures; repeat the scenario')
        subprocess.run(['python3', '-B', str(Path(__file__).with_name('measure_shell.py')),
                        '--pid', str(fresh_pid), '--seconds', '60', '--label', f'fresh-idle-{index}',
                        '--output', str(directory / f'idle-{index}.json')], check=True, timeout=90)
        assert_idle_media()
    print('Measurements:', directory)
    print('Idle snapshots only; UI, playback and animation workloads are still required.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit('Baseline capture stopped: ' + str(error))
