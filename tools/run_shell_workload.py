#!/usr/bin/env python3
"""Run an observable, single-display dock workload without editing preferences."""
import argparse
import hashlib
import json
import os
import resource
from pathlib import Path
import subprocess
import tempfile
import time

from capture_shell_baseline import assert_idle_media, run
from measure_shell import discover_pid, frame_call, process_sample, tree_sample

PLAN = [('launcher', 20), ('settings', 10), ('dashboard', 1), ('activity', 1),
        ('calendar', 1), ('audio', 1), ('wifi', 1), ('bluetooth', 1),
        ('battery', 1), ('notifications', 1), ('power', 1)]
TIMEOUT = 12
DWELL = 0.5
SETTLE = 3


def input_hashes():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    paths = [config / 'quickshell' / name for name in
             ('shell.qml', 'Hyprdock.qml', 'FrameTiming.qml', 'WorkloadControl.qml')]
    paths.append(config / 'hyprshell/settings.json')
    return {str(p.relative_to(config)): hashlib.sha256(p.read_bytes()).hexdigest()
            if p.exists() else None for p in paths}


def check_state(state, instance):
    if state.get('instance') != instance:
        raise RuntimeError('Shell reloaded during workload; do not compare this run')
    if not state.get('supported') or not state.get('safe') or state.get('otherUiOpen'):
        raise RuntimeError('Unsupported state, another overlay, or pending Settings edits')


def wait_state(instance, page):
    deadline = time.monotonic() + TIMEOUT
    stable = 0
    while time.monotonic() < deadline:
        state = frame_call('workloadState')
        check_state(state, instance)
        dock = state['dock']
        ready = (dock['section'] == page and dock['expanded'] and dock['pageReady']
                 and dock['surfaceVisible']) if page else (
                     not dock['section'] and not dock['expanded'] and not state['settingsOpen'])
        stable = stable + 1 if ready and dock['settled'] and not state.get('busy') else 0
        if stable >= 3:
            return state
        time.sleep(0.1)
    raise RuntimeError(f'Timed out waiting for {page or "closed UI"}; last state: {state}')


def snapshot(pid):
    result = process_sample(pid)
    result['tree'] = tree_sample(pid)
    result['time'] = time.monotonic()
    return result


def transition(instance, page, refresh):
    session = frame_call('startWorkloadFrames', TIMEOUT + 5, refresh)
    if not session.get('ok'):
        raise RuntimeError('Another frame capture is active; workload stopped')
    frames = None
    started = time.monotonic()
    try:
        result = frame_call('workloadOpen', page) if page else frame_call('workloadClose')
        if not result.get('ok'):
            raise RuntimeError(result.get('error', 'UI action failed'))
        state = wait_state(instance, page)
    finally:
        # Do not finish an unrelated capture belonging to a new shell generation.
        if frame_call('workloadState').get('instance') == instance:
            frames = frame_call('frameResults')
    if frames is None or frames['instance'] != session['instance'] or frames['capture'] != session['capture']:
        raise RuntimeError('Frame capture identity changed')
    return {'page': page, 'command_to_settled_seconds': time.monotonic() - started,
            'state': state, 'frames': frames}


def execute(pid, initial, refresh, report, plan=PLAN):
    instance = initial['instance']
    report['before'] = snapshot(pid)
    for page, repetitions in plan:
        assert_idle_media()
        block = {'page': page, 'repetitions': repetitions, 'cycles': [], 'before': snapshot(pid)}
        report['blocks'].append(block)
        print(f'{page}: {repetitions} open/close cycles', flush=True)
        for cycle in range(repetitions):
            row = {'cycle': cycle + 1, 'before': snapshot(pid)}
            block['cycles'].append(row)
            row['open'] = transition(instance, page, refresh)
            time.sleep(DWELL)
            row['close'] = transition(instance, '', refresh)
            time.sleep(DWELL)
            row['after'] = snapshot(pid)
            if row['before']['start'] != row['after']['start']:
                raise RuntimeError('Shell process changed during workload')
        time.sleep(SETTLE)
        wait_state(instance, '')
        block['settled'] = snapshot(pid)
    assert_idle_media()
    report['after'] = snapshot(pid)


def restore(initial, cursor):
    state = frame_call('workloadState')
    check_state(state, initial['instance'])
    result = frame_call('workloadClose')
    if not result.get('ok'):
        raise RuntimeError(result.get('error', 'Cannot restore UI'))
    wait_state(initial['instance'], '')
    if initial['focusedWindow'] and not frame_call('workloadRestoreFocus', initial['focusedWindow']):
        raise RuntimeError('Original application no longer available to focus')
    x, y = int(cursor['x']), int(cursor['y'])
    run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{ x = {x}, y = {y} }})')
    wait_state(initial['instance'], '')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assert_idle_media()
    initial = frame_call('workloadState')
    check_state(initial, initial['instance'])
    if initial['dock']['expanded'] or initial['settingsOpen']:
        raise RuntimeError('Close all shell menus and Settings before running this workload')
    monitors = json.loads(run('hyprctl', '-j', 'monitors'))
    if len(monitors) != 1:
        raise RuntimeError('This workload currently requires one display and dock mode')
    cursor = json.loads(run('hyprctl', '-j', 'cursorpos'))
    pid = discover_pid()
    output = args.output or Path(tempfile.mkdtemp(prefix='hyprshell-workload-', dir='/tmp')) / 'workload.json'
    report = {'version': 1, 'status': 'running', 'initial': initial, 'pid': pid,
              'driver_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'input_hashes': input_hashes(),
              'display': {k: monitors[0][k] for k in ('name', 'width', 'height', 'scale', 'refreshRate')},
              'refresh_hz': monitors[0]['refreshRate'], 'plan': PLAN, 'dwell_seconds': DWELL,
              'settle_seconds': SETTLE, 'timeout_seconds': TIMEOUT, 'blocks': [],
              'limits': 'Single-display dock scenario only; no input clicks or settings edits. '
                        'Command-to-settled includes IPC/polling overhead; it is not icon-miss latency. '
                        'Frame swaps are not GPU time; >250 ms gaps remain separate from active intervals. '
                        'Snapshots can miss short-lived helpers. Driver child CPU is reported separately. '
                        'Keep pointer and keyboard idle, media paused, and check animations visually.'}
    print('Workload report:', output, flush=True)
    with output.open('x') as stream:
        cpu = time.process_time()
        children = resource.getrusage(resource.RUSAGE_CHILDREN)
        try:
            wait_state(initial['instance'], '')
            execute(pid, initial, monitors[0]['refreshRate'], report)
            report['status'] = 'completed'
        except (Exception, KeyboardInterrupt) as error:
            report['status'] = 'failed'
            report['error'] = str(error) or type(error).__name__
        finally:
            try:
                restore(initial, cursor)
                report['restored'] = True
            except Exception as error:
                report['restored'] = False
                report['restore_error'] = str(error)
                report['status'] = 'failed'
            end = resource.getrusage(resource.RUSAGE_CHILDREN)
            report['driver_cpu_seconds'] = time.process_time() - cpu
            report['driver_child_cpu_seconds'] = end.ru_utime + end.ru_stime - children.ru_utime - children.ru_stime
            report['final_input_hashes'] = input_hashes()
            if report['final_input_hashes'] != report['input_hashes']:
                report['status'] = 'failed'
                report['input_error'] = 'Probe files or saved settings changed during workload; capture is not comparable'
            json.dump(report, stream, indent=2)
            stream.write('\n')
    if report['status'] != 'completed':
        raise RuntimeError(f'Workload incomplete; inspect {output}: '
                           + str(report.get('error') or report.get('restore_error') or report.get('input_error')))
    print('Measurements:', output)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit('Workload stopped: ' + str(error))
