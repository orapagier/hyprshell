"""Small file transactions shared by on-demand desktop preference helpers."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path

from backend import atomic


def roots():
    return (Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config'),
            Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'hyprshell')


def revision(paths):
    digest = hashlib.sha256()
    for path in paths:
        digest.update(str(path).encode()); digest.update(b'\0')
        digest.update(path.read_bytes() if path.exists() else b'<missing>'); digest.update(b'\0')
    return digest.hexdigest()


def transaction(changes, prefix, activate=None):
    changes = {path: text for path, text in changes.items() if not path.exists() or path.read_text() != text}
    if not changes:
        return None
    _, state = roots()
    backup = state / 'backups' / (prefix + '-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(parents=True, mode=0o700)
    previous = {path: path.read_text() if path.exists() else None for path in changes}
    manifest = []
    for index, (path, text) in enumerate(previous.items()):
        manifest.append({'path': str(path), 'existed': text is not None, 'file': str(index)})
        if text is not None:
            atomic(backup / str(index), text)
    atomic(backup / 'manifest.json', json.dumps(manifest, indent=2))
    applied = []
    try:
        for path, text in changes.items():
            atomic(path, text); applied.append(path)
        if activate:
            activate()
    except Exception:
        for path in reversed(applied):
            if previous[path] is None:
                path.unlink(missing_ok=True)
            else:
                atomic(path, previous[path])
        raise
    return str(backup)


def managed_block(original, label, lines):
    begin, end = '# BEGIN Hyprshell ' + label, '# END Hyprshell ' + label
    block = begin + '\n' + '\n'.join(lines) + '\n' + end
    if begin in original:
        if original.count(begin) != 1 or original.count(end) != 1:
            raise ValueError('The managed ' + label + ' block is incomplete. Repair it before applying.')
        start = original.index(begin); finish = original.index(end, start) + len(end)
        return original[:start] + block + original[finish:]
    if end in original:
        raise ValueError('The managed ' + label + ' block is incomplete. Repair it before applying.')
    return original.rstrip() + '\n\n' + block + '\n'
