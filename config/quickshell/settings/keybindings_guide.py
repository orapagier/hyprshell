#!/usr/bin/env python3
"""Read every runtime binding, retaining Lua key names omitted from JSON."""
import json
import re
import subprocess
import sys


def named_bindings(rows, text):
    # Hyprland 0.56 exposes displayKey only in the text form of `binds`.
    # Match complete registry snapshots before pairing rows, including duplicates.
    blocks = re.split(r'^bind[a-z]*\n', text, flags=re.MULTILINE)[1:]
    if len(blocks) != len(rows):
        raise ValueError('Shortcut registry changed while reading it')
    result = []
    for row, block in zip(rows, blocks):
        fields = dict(re.findall(r'^\t(modmask|submap|key|keycode|catchall|description|dispatcher): (.*)$',
                                 block, flags=re.MULTILINE))
        expected = {'modmask': str(row['modmask']), 'submap': row['submap'],
                    'keycode': str(row['keycode']),
                    'catchall': 'true' if row['catch_all'] else 'false',
                    'description': row['description'], 'dispatcher': row['dispatcher']}
        if any(fields.get(key) != value for key, value in expected.items()):
            raise ValueError('Shortcut registry changed while reading it')
        if row['key'] and fields.get('key') != row['key']:
            raise ValueError('Shortcut registry changed while reading it')
        result.append(dict(row, key=row['key'] or fields.get('key', '')))
    return result


def read_bindings():
    def read(*args):
        return subprocess.run(['hyprctl', *args], check=True, capture_output=True,
                              text=True, timeout=5).stdout
    rows = json.loads(read('-j', 'binds'))
    if not isinstance(rows, list):
        raise ValueError('Expected a binding list')
    # Legacy configurations already supply names; catch-all and code bindings
    # legitimately have no symbol. Lua symbol bindings have neither field.
    if any(not row.get('key') and not row.get('keycode') and not row.get('catch_all') for row in rows):
        rows = named_bindings(rows, read('binds'))
    return rows


if __name__ == '__main__':
    try:
        print(json.dumps(read_bindings()))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('Could not read desktop shortcuts: ' + str(error), file=sys.stderr)
        sys.exit(1)
