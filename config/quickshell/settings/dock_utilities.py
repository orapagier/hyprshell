#!/usr/bin/env python3
"""Dock file-manager actions. Only the explicit confirmation action empties Trash."""
import json
from pathlib import Path
import subprocess
import sys


def action(name, run=subprocess.run):
    commands = {'status': ['gio', 'list', 'trash:///'],
                'files': ['gio', 'open', str(Path.home())],
                'trash': ['gio', 'open', 'trash:///'],
                'empty-confirmed': ['gio', 'trash', '--empty']}
    if name not in commands:
        raise ValueError('Unknown dock utility')
    result = run(commands[name], capture_output=True, text=True, timeout=20, check=False)
    if result.returncode:
        return {'ok': False, 'message': 'Trash is unavailable.' if name == 'status' else 'The file manager action failed.'}
    return {'ok': True, **({'full': bool(result.stdout.strip())} if name == 'status' else {})}


if __name__ == '__main__':
    try:
        print(json.dumps(action(sys.argv[1])))
    except (IndexError, ValueError, OSError, subprocess.SubprocessError):
        print(json.dumps({'ok': False, 'message': 'The file manager action could not be completed.'}))
