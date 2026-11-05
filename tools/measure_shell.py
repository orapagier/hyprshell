#!/usr/bin/env python3
"""Sample shell and descendant resources; run in a desktop terminal for baselines."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


def process_sample(pid, proc=Path('/proc')):
    raw = (proc / str(pid) / 'stat').read_text()
    fields = raw[raw.rfind(')') + 2:].split()
    # fields starts at stat field 3 (state); names may contain spaces or ')'.
    return {'ticks': int(fields[11]) + int(fields[12]),
            'ppid': int(fields[1]),
            'start': int(fields[19]),
            'rss_bytes': int(fields[21]) * os.sysconf('SC_PAGE_SIZE')}


def counters(path):
    return {key: value.strip() for key, value in
            (line.split(':', 1) for line in path.read_text().splitlines() if ':' in line)}


def tree_sample(pid, proc=Path('/proc')):
    """Best-effort snapshot. Missing data is explicit, never counted as zero."""
    started = time.monotonic()
    processes = {}
    errors = []
    for entry in proc.iterdir():
        if entry.name.isdecimal():
            try:
                processes[int(entry.name)] = process_sample(int(entry.name), proc)
            except OSError:
                # Unrelated processes can disappear while discovering descendants.
                continue
    if pid not in processes:
        raise ValueError('Shell unavailable during process-tree discovery')
    selected = {pid}
    while True:
        children = {p for p, row in processes.items() if row['ppid'] in selected}
        expanded = selected | children
        if expanded == selected:
            break
        selected = expanded
    result = {}
    for process in sorted(selected):
        path = proc / str(process)
        row = dict(processes[process], pid=process, pss_bytes=None, fds=None, threads={},
                   memory_bytes={}, name=None)
        try:
            memory = counters(path / 'smaps_rollup')
            row['pss_bytes'] = int(memory['Pss'].split()[0]) * 1024
            row['memory_bytes'] = {key: int(memory[key].split()[0]) * 1024 for key in
                                   ('Pss_Anon', 'Pss_File', 'Pss_Shmem', 'Private_Clean',
                                    'Private_Dirty', 'Anonymous', 'SwapPss') if key in memory}
        except (OSError, KeyError, ValueError) as error:
            errors.append(f'{process}: PSS unavailable: {error}')
        try:
            # No command line: helper arguments can contain private desktop data.
            row['name'] = (path / 'comm').read_text().strip()
        except OSError:
            pass
        try:
            row['fds'] = len(list((path / 'fd').iterdir()))
        except OSError as error:
            errors.append(f'{process}: FDs unavailable: {error}')
        try:
            for task in (path / 'task').iterdir():
                try:
                    identity = process_sample(int(task.name), path / 'task')['start']
                    status = counters(task / 'status')
                    thread = {name: int(status[name]) for name in
                              ('voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches')}
                    thread['name'] = status.get('Name')
                    try:
                        values = list(map(int, (task / 'schedstat').read_text().split()))
                        thread.update(zip(('runtime_ns', 'runqueue_wait_ns', 'timeslices'), values[:3]))
                    except OSError:
                        # schedstat is optional on kernels without scheduling stats.
                        pass
                    row['threads'][f'{task.name}:{identity}'] = thread
                except (OSError, KeyError, ValueError) as error:
                    errors.append(f'{process}/{task.name}: thread unavailable: {error}')
            if process_sample(process, proc)['start'] != row['start']:
                errors.append(f'{process}: PID reused during snapshot')
        except OSError as error:
            errors.append(f'{process}: process exited or inaccessible: {error}')
        result[f'{process}:{row["start"]}'] = row
    return {'processes': result, 'errors': errors,
            'collection_seconds': time.monotonic() - started}


def memory_snapshots_complete(samples, pid):
    if len(samples) < 2:
        return False
    identities = set()
    for sample in samples:
        tree = sample['tree']
        if tree['errors']:
            return False
        roots = [key for key, row in tree['processes'].items() if row['pid'] == pid]
        if len(roots) != 1:
            return False
        identities.add(roots[0])
        if any(not isinstance(row.get('pss_bytes'), int) or row['pss_bytes'] < 0
               for row in tree['processes'].values()):
            return False
    return len(identities) == 1


def summarize_tree(samples, pid):
    """Scheduling/CPU deltas cover observed lifetimes only, including all threads."""
    totals = {name: 0 for name in ('voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches',
                                  'runtime_ns', 'runqueue_wait_ns', 'timeslices')}
    observed = {name: False for name in totals}
    created, exited, threads_created, threads_exited = set(), set(), set(), set()
    cpu_ticks = 0
    complete = all(not s['tree']['errors'] for s in samples)
    for before, after in zip(samples, samples[1:]):
        old, new = before['tree']['processes'], after['tree']['processes']
        created.update(new.keys() - old.keys())
        exited.update(old.keys() - new.keys())
        old_threads = {f'{p}/{t}': v for p, r in old.items() for t, v in r['threads'].items()}
        new_threads = {f'{p}/{t}': v for p, r in new.items() for t, v in r['threads'].items()}
        threads_created.update(new_threads.keys() - old_threads.keys())
        threads_exited.update(old_threads.keys() - new_threads.keys())
        for key in old.keys() & new.keys():
            delta = new[key]['ticks'] - old[key]['ticks']
            if delta < 0:
                complete = False
            else:
                cpu_ticks += delta
        for key in old_threads.keys() & new_threads.keys():
            for name in totals:
                if name in old_threads[key] and name in new_threads[key]:
                    delta = new_threads[key][name] - old_threads[key][name]
                    if delta < 0:
                        complete = False
                    else:
                        totals[name] += delta
                        observed[name] = True
    memory = {'shell': [], 'helpers': [], 'tree': []}
    per_process = {}
    counts = {name: [] for name in ('processes', 'threads', 'fds')}
    for sample in samples:
        rows = list(sample['tree']['processes'].values())
        for identity, row in sample['tree']['processes'].items():
            per_process.setdefault(identity, []).append(row)
        counts['processes'].append(len(rows))
        counts['threads'].append(sum(len(r['threads']) for r in rows))
        counts['fds'].append(None if any(r['fds'] is None for r in rows)
                             else sum(r['fds'] for r in rows))
        for name, group in (('shell', [r for r in rows if r['pid'] == pid]),
                            ('helpers', [r for r in rows if r['pid'] != pid]), ('tree', rows)):
            memory[name].append(None if any(r['pss_bytes'] is None for r in group)
                                else sum(r['pss_bytes'] for r in group) / 1048576)
    elapsed = samples[-1]['time'] - samples[0]['time']
    return {'observed_lifetimes_complete': complete and not any(
                (created, exited, threads_created, threads_exited)),
            'memory_snapshots_complete': memory_snapshots_complete(samples, pid),
            'processes_created': sorted(created), 'processes_exited': sorted(exited),
            'threads_created': sorted(threads_created), 'threads_exited': sorted(threads_exited),
            'observed_cpu_percent_one_core': 100 * cpu_ticks / os.sysconf('SC_CLK_TCK') / elapsed,
            'scheduling_deltas': {k: v if observed[k] else None for k, v in totals.items()},
            'pss_mib_median': {k: statistics.median(v) if all(x is not None for x in v)
                               else None for k, v in memory.items()},
            'tree_counts': {k: {'min': min(v), 'max': max(v)}
                            if all(x is not None for x in v) else None for k, v in counts.items()},
            'process_pss': {identity: {
                'name': rows[-1].get('name'), 'pid': rows[-1]['pid'],
                'role': 'shell' if rows[-1]['pid'] == pid else 'helper',
                'observed_samples': len(rows),
                'pss_mib_median': statistics.median(r['pss_bytes'] for r in rows) / 1048576
                    if all(r['pss_bytes'] is not None for r in rows) else None
            } for identity, rows in per_process.items()},
            'collection_seconds_total': sum(s['tree']['collection_seconds'] for s in samples)}


def summarize(samples):
    if len(samples) < 2:
        raise ValueError('At least two samples are required')
    if len({sample['start'] for sample in samples}) != 1:
        raise ValueError('Shell restarted during capture; repeat this scenario')
    elapsed = samples[-1]['time'] - samples[0]['time']
    ticks = samples[-1]['ticks'] - samples[0]['ticks']
    rss = [s['rss_bytes'] / 1048576 for s in samples]
    return {'duration_seconds': round(elapsed, 3),
            'cpu_percent_one_core': round(100 * ticks / os.sysconf('SC_CLK_TCK') / elapsed, 3),
            'rss_mib_median': round(statistics.median(rss), 3),
            'rss_mib_peak': round(max(rss), 3), 'samples': len(samples)}


def discover_pid():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'quickshell'
    result = subprocess.run(['quickshell', 'list', '--path', str(config), '--json'],
                            check=True, capture_output=True, text=True, timeout=5)
    instances = json.loads(result.stdout)
    if not isinstance(instances, list) or len(instances) != 1:
        raise ValueError('Expected one desktop shell; supply --pid explicitly')
    return int(instances[0]['pid'])


def frame_call(method, *args):
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'quickshell'
    result = subprocess.run(['quickshell', 'ipc', '--path', str(config), 'call', 'performance',
                             method, *map(str, args)], check=True, capture_output=True, text=True, timeout=5)
    return json.loads(result.stdout)


def collect_samples(pid, seconds):
    samples = []
    start = time.monotonic()
    while True:
        sample = process_sample(pid)
        sample['tree'] = tree_sample(pid)
        sample['time'] = time.monotonic() - start
        samples.append(sample)
        elapsed = sample['time'] - samples[0]['time']
        if elapsed >= seconds:
            return samples
        time.sleep(min(1, seconds - elapsed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int)
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--label', default='idle')
    parser.add_argument('--frames', action='store_true', help='Also capture opt-in frame-swap intervals via shell IPC')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.seconds < 1 or args.seconds > 3600:
        parser.error('--seconds must be between 1 and 3600')
    if args.frames and args.pid is not None:
        parser.error('--frames discovers the desktop PID; omit --pid')
    if args.output.exists():
        parser.error('--output already exists; choose a new filename')
    pid = args.pid if args.pid is not None else discover_pid()
    frame_session = frame_call('startFrames', int(args.seconds) + 1) if args.frames else None
    if frame_session and not frame_session.get('ok'):
        raise ValueError('Another frame capture is active; wait for it to finish')
    try:
        samples = collect_samples(pid, args.seconds)
    finally:
        frames = frame_call('frameResults') if frame_session else None
    if frames and (frames['instance'] != frame_session['instance'] or frames['capture'] != frame_session['capture']):
        raise ValueError('Shell reloaded during frame capture; repeat this scenario')
    report = {'label': args.label, 'pid': pid, 'summary': summarize(samples), 'samples': samples,
              'tree_summary': summarize_tree(samples, pid),
              'limits': 'Process-tree snapshots at approximately 1 s intervals; short-lived processes/threads '
                        'between snapshots and reparented helpers may be missed. Churn makes CPU/scheduling '
                        'deltas incomplete. Context switches and schedstat are scheduling proxies, not wakeups; '
                        'schedstat can be absent or disabled (zeros). GPU memory excluded. Collection overhead '
                        'is reported separately. Frame swaps are not GPU render time.'}
    if frames:
        report['frames'] = frames
    # Avoid overwriting a baseline or following a pre-existing output symlink.
    with args.output.open('x') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    print(json.dumps(report['summary'], indent=2))
    print('Saved:', args.output)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit('Measurement unavailable: ' + str(error))
