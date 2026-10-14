#!/usr/bin/env python3
"""Save dependency evidence for a rolling CI run; this is not a hardware test."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import compatibility


def report():
    info = compatibility.machine()
    packages = (['rpm', '-q', 'hyprland', 'quickshell', 'qt6-qtbase', 'qt6-qtdeclarative', 'uwsm']
                if info['distribution'] == 'fedora' else
                ['pacman', '-Q', 'hyprland', 'quickshell', 'qt6-base', 'qt6-declarative', 'uwsm'])
    result = subprocess.run(packages, capture_output=True, text=True, timeout=20)
    revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    return {'created': datetime.now(timezone.utc).isoformat(), 'revision': revision,
            'scope': 'Dependency snapshot only. Consult the CI job result for automated tests; no physical acceptance is implied.',
            'packages': result.stdout.splitlines(), 'packageQuerySucceeded': result.returncode == 0,
            'assessment': compatibility.assess(json.loads((ROOT / 'compatibility.json').read_text()), info)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(report(), indent=2) + '\n')
