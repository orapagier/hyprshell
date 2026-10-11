#!/usr/bin/env python3
"""Opt-in bounded clipboard history; contents never enter config or logs."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from backend import read_preferences
from preferences import roots
from optional_tools import install

LIMIT = 5 * 1024 * 1024


def command(action):
    _, state = roots()
    directory = state / 'clipboard'
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    settings = read_preferences()['clipboard']
    return ['cliphist', '-config-path', '/dev/null', '-db-path', str(directory / 'db'),
            '-max-items', str(int(settings['maxItems'])), '-max-store-size', str(LIMIT), action]


def clean_env():
    return {key: value for key, value in os.environ.items() if not key.startswith('CLIPHIST_')}


def run(action, data=None):
    result = subprocess.run(command(action), input=data, capture_output=True, timeout=10, env=clean_env())
    if result.returncode:
        raise ValueError('Clipboard history could not be accessed. Install the tools, check desktop access, and refresh.')
    return result.stdout


def watch():
    settings = read_preferences()['clipboard']
    if not settings['enabled']: return 0
    if not all(shutil.which(tool) for tool in ('wl-paste', 'cliphist', 'wl-copy')):
        raise ValueError('Install clipboard tools, then disable and enable history to retry.')
    args = ['wl-paste']
    if not settings['includeImages']: args += ['--type', 'text']
    args += ['--watch', sys.executable, str(Path(__file__).resolve()), '--store']
    os.execvp(args[0], args)


def store():
    settings = read_preferences()['clipboard']
    if not settings['enabled'] or os.environ.get('CLIPBOARD_STATE') in ('sensitive', 'nil', 'clear'):
        return 0
    data = sys.stdin.buffer.read(LIMIT + 1)
    if 0 < len(data) <= LIMIT: run('store', data)
    return 0


def request(payload):
    operation = payload.get('operation')
    if operation == 'install': return install('clipboard')
    if operation == 'status':
        return {'ok': True, 'available': all(shutil.which(tool) for tool in ('wl-paste', 'cliphist', 'wl-copy'))}
    if operation == 'list':
        if not (roots()[1] / 'clipboard/db').is_file(): return {'ok': True, 'entries': []}
        entries = []
        for line in run('list').decode('utf-8', errors='replace').splitlines():
            ident, sep, preview = line.partition('\t')
            if sep and re.fullmatch(r'[0-9]{1,20}', ident):
                entries.append({'id': ident, 'preview': preview[:200]})
        return {'ok': True, 'entries': entries[:int(read_preferences()['clipboard']['maxItems'])]}
    if operation == 'wipe':
        if payload.get('confirmed') is not True: raise ValueError('Confirm clearing clipboard history first.')
        if (roots()[1] / 'clipboard/db').exists(): run('wipe')
        return {'ok': True, 'entries': [], 'message': 'Saved clipboard history cleared. The current clipboard is unchanged.'}
    if operation in ('copy', 'delete'):
        ident = payload.get('id')
        if not isinstance(ident, str) or not re.fullmatch(r'[0-9]{1,20}', ident): raise ValueError('Choose an entry from history.')
        if operation == 'delete': run('delete', (ident + '\n').encode())
        else:
            data = run('decode', (ident + '\n').encode())
            result = subprocess.run(['wl-copy'], input=data, capture_output=True, timeout=10)
            if result.returncode: raise ValueError('Could not copy the entry. Try again in the desktop session.')
        return {'ok': True, 'removed': ident if operation == 'delete' else '', 'message': 'Entry copied.' if operation == 'copy' else 'Entry removed.'}
    raise ValueError('Unknown clipboard operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json'); parser.add_argument('--watch', action='store_true'); parser.add_argument('--store', action='store_true'); args = parser.parse_args()
    try:
        if args.watch: return watch()
        if args.store: return store()
        result = request(json.loads(args.request_json))
    except (ValueError, OSError, subprocess.SubprocessError):
        if args.watch or args.store:
            print('Clipboard history stopped. Install the clipboard tools or check desktop access.', file=sys.stderr); return 1
        result = {'ok': False, 'message': 'Clipboard operation failed. Install the tools, check desktop access, and refresh.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__': sys.exit(main())
