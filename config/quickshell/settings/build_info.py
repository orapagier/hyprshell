"""Identify deployed code independently of a checkout's later local commits."""
import json
import os
from pathlib import Path
import subprocess


def repository(repo):
    def git(*args):
        try:
            return subprocess.check_output(['git', '-C', str(repo), *args],
                                           stderr=subprocess.DEVNULL, text=True, timeout=10).strip()
        except (OSError, subprocess.SubprocessError):
            return ''
    revision = git('rev-parse', 'HEAD')
    return {'channel': 'rolling', 'revision': revision or None,
            'date': git('show', '-s', '--format=%cs', 'HEAD') or None,
            'upstream_revision': None,
            'modified': bool(git('status', '--porcelain', '--untracked-files=normal'))}


def installed():
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'hyprshell'
    try:
        build = json.loads((state / 'deployed.json').read_text()).get('build') or {}
    except (OSError, ValueError):
        build = {}
    revision = build.get('upstream_revision') or build.get('revision')
    label = 'Hyprshell Rolling'
    if revision:
        label += ' · ' + (build.get('date') or 'date unknown') + ' · ' + revision[:12]
        if build.get('modified'):
            label += ' · local changes'
    else:
        label += ' · build not recorded'
    return {**build, 'label': label}
