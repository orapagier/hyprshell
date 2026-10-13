#!/usr/bin/env python3
"""Create a local evidence record, or verify a completed acceptance report."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import compatibility
from check_daily_driver import check

CHECKLIST = ['Session', 'Displays', 'Input', 'Network', 'Sound', 'Lock/power',
             'Applications', 'Portals', 'Update/recovery', 'Fresh Fedora VM installation']


def verify(report):
    errors = []
    if report.get('format') != 1 or not report.get('revision') or not report.get('afterLogin'):
        errors.append('A revision and an after-login format 1 report are required.')
    if report.get('dirty'):
        errors.append('Test a committed candidate revision.')
    if not report.get('compatibility', {}).get('compatible'):
        errors.append('Compatibility checks must pass.')
    rows = report.get('manual', {})
    for title in CHECKLIST:
        row = rows.get(title, {})
        if row.get('status') not in ('pass', 'not-applicable'):
            errors.append(title + ': pending or failed')
        elif row['status'] == 'not-applicable' and (not row.get('note', '').strip() or title in ('Session', 'Fresh Fedora VM installation', 'Update/recovery')):
            errors.append(title + ': requires a test or an explanation')
    automated = report.get('readiness', {}).get('checks', [])
    if not automated:
        errors.append('Readiness evidence is missing.')
    for row in automated:
        if row.get('state') != 'ok':
            note = report.get('exceptions', {}).get(row.get('title', ''), '')
            if row.get('state') == 'unavailable' or not isinstance(note, str) or not note.strip():
                errors.append(row.get('title', 'Readiness') + ': unresolved automated check')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--after-login', action='store_true')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        errors = verify(json.loads(args.verify.read_text()))
        print('\n'.join(errors) if errors else 'Acceptance record complete (manual results are user-reported).')
        return int(bool(errors))
    if not args.output:
        parser.error('--output is required to create a report')
    info = compatibility.machine()
    revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True).strip())
    report = {'format': 1, 'created': datetime.now(timezone.utc).isoformat(), 'revision': revision,
              'dirty': dirty, 'afterLogin': args.after_login,
              'compatibility': compatibility.assess(json.loads((ROOT / 'compatibility.json').read_text()), info),
              'readiness': check(args.after_login), 'exceptions': {},
              'manual': {name: {'status': 'pending', 'note': ''} for name in CHECKLIST}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('Saved local acceptance template:', args.output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
