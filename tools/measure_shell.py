#!/usr/bin/env python3
"""Sample shell CPU/RSS from /proc; run in a terminal in the desktop session."""
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
            'start': int(fields[19]),
            'rss_bytes': int(fields[21]) * os.sysconf('SC_PAGE_SIZE')}


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
    samples = []
    start = time.monotonic()
    try:
        while True:
            sample = process_sample(pid)
            sample['time'] = time.monotonic() - start
            samples.append(sample)
            if sample['time'] >= args.seconds:
                break
            time.sleep(min(1, args.seconds - sample['time']))
    finally:
        frames = frame_call('frameResults') if frame_session else None
    if frames and (frames['instance'] != frame_session['instance'] or frames['capture'] != frame_session['capture']):
        raise ValueError('Shell reloaded during frame capture; repeat this scenario')
    report = {'label': args.label, 'pid': pid, 'summary': summarize(samples), 'samples': samples,
              'limits': 'Shell process only; excludes child processes, GPU memory and frame timing.'}
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
