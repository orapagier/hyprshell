#!/usr/bin/env python3
"""Screen matched PSS captures against audit gates; never approves a deployment."""
import argparse
import json
import math
from pathlib import Path
import statistics

from measure_shell import memory_snapshots_complete


def gate(before, after, *, absolute, percent=0, resolution=1 / 1024):
    if len(before) != len(after) or len(before) < 3:
        raise ValueError('Supply at least three matched runs in each set')
    if any(not isinstance(v, (float, int)) or not math.isfinite(v) or v < 0
           for v in before + after):
        raise ValueError('Metrics must be available, finite and nonnegative')
    baseline, result = statistics.median(before), statistics.median(after)
    variation = max(max(before) - min(before), max(after) - min(after))
    improvement = baseline - result
    threshold = max(absolute, baseline * percent / 100)
    passed = improvement >= threshold and improvement > max(2 * variation, resolution)
    return {'status': 'metric_pass' if passed else 'inconclusive',
            'before_median_mib': baseline, 'after_median_mib': result,
            'improvement_mib': improvement, 'larger_variation_mib': variation,
            'minimum_improvement_mib': threshold, 'resolution_mib': resolution,
            'runs_per_set': len(before),
            'next': 'Verify other resource, behavior and animation gates before acceptance.' if passed
                    else 'Use at least five longer matched runs for noisy/borderline results; do not accept yet.'}


def read_metric(path, metric):
    report = json.loads(path.read_text())
    samples = report['samples']
    if len(samples) < 2 or samples[-1]['time'] - samples[0]['time'] < 60:
        raise ValueError(f'{path}: capture shorter than the 60 s baseline minimum')
    if not memory_snapshots_complete(samples, report['pid']):
        raise ValueError(f'{path}: incomplete memory snapshots or changed shell identity')
    return report['tree_summary']['pss_mib_median'][metric]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate', choices=('phase2-pss', 'phase3-pss'), required=True)
    parser.add_argument('--before', nargs='+', type=Path, required=True)
    parser.add_argument('--after', nargs='+', type=Path, required=True)
    args = parser.parse_args()
    paths = args.before + args.after
    if len({p.resolve() for p in paths}) != len(paths):
        parser.error('Each run must be a distinct capture file')
    metric = 'tree' if args.gate == 'phase2-pss' else 'helpers'
    result = gate([read_metric(p, metric) for p in args.before],
                  [read_metric(p, metric) for p in args.after], absolute=5,
                  percent=25 if args.gate == 'phase3-pss' else 0)
    result['limits'] = ('Metric screen only. Caller must verify matched scenarios, fixtures and settling. '
                        'Phase 2 plateau/long-session evidence and other behavior/resource gates are separate. '
                        'Phase 3 captures must include the complete replacement helper tree.')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit('Comparison unavailable: ' + str(error))
