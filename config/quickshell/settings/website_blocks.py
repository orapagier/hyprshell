#!/usr/bin/env python3
"""Managed local hostname blocks, separate from firewalld and desktop sync."""
import fcntl
import hashlib
import ipaddress
import os
from pathlib import Path
import re
import stat
import tempfile
from urllib.parse import urlsplit

HOSTS = Path('/etc/hosts')
LOCK = Path('/run/lock/hyprshell-websites.lock')
BEGIN = '# BEGIN HYPRSHELL WEBSITE BLOCKS\n'
END = '# END HYPRSHELL WEBSITE BLOCKS\n'


def domain(value):
    if not isinstance(value, str) or not value.strip() or any(c in value for c in '\r\n\0'):
        raise ValueError('Enter a website name, such as example.com.')
    value = value.strip()
    if '://' in value:
        parsed = urlsplit(value)
        if parsed.scheme not in ('http', 'https') or parsed.username or parsed.password or parsed.port:
            raise ValueError('Enter a website name without a username or port.')
        value = parsed.hostname or ''
    elif '/' in value or ':' in value:
        raise ValueError('Enter the website name, such as example.com, or paste an http/https link.')
    value = value.rstrip('.').lower()
    if value.startswith('www.'):
        value = value[4:]
    try:
        value = value.encode('idna').decode('ascii')
    except UnicodeError:
        raise ValueError('Enter a valid website name.') from None
    labels = value.split('.')
    if len(value) > 253 or len(labels) < 2 or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels):
        raise ValueError('Enter a website name, such as example.com.')
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return value
    raise ValueError('Use Block an IP address for numeric addresses.')


def content(domains):
    if not domains:
        return ''
    lines = [BEGIN]
    for name in sorted(domains):
        lines += ['# website: ' + name + '\n', '0.0.0.0 ' + name + ' www.' + name + '\n',
                  ':: ' + name + ' www.' + name + '\n']
    return ''.join(lines) + END


def read():
    if HOSTS.is_symlink() or not stat.S_ISREG(HOSTS.stat().st_mode) or HOSTS.stat().st_size > 1048576:
        raise ValueError('The system website file cannot be safely edited here.')
    text = HOSTS.read_text(encoding='utf-8')
    names = []
    if BEGIN in text or END in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ValueError('The saved website block list needs repair before editing.')
        start = text.index(BEGIN); stop = text.index(END) + len(END)
        if stop <= start:
            raise ValueError('The saved website block list needs repair before editing.')
        if start and text[start - 1] != '\n':
            raise ValueError('The saved website block marker is malformed.')
        block = text[start:stop]
        names = [domain(line[len('# website: '):]) for line in block.splitlines() if line.startswith('# website: ')]
        if len(set(names)) != len(names) or content(names) != block:
            raise ValueError('The saved website block list was manually changed. Review it before editing here.')
    return text, names, hashlib.sha256(text.encode()).hexdigest()


def status():
    _, names, revision = read()
    return {'websiteRevision': revision, 'websites': [
        {'id': 'website-' + hashlib.sha256(name.encode()).hexdigest()[:16], 'kind': 'website',
         'value': name, 'raw': name, 'title': 'Website: ' + name,
         'now': True, 'saved': True, 'editable': True} for name in names]}


def atomic(path, text, metadata, private=False):
    fd, temporary = tempfile.mkstemp(prefix='.hyprshell-websites-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(text); stream.flush()
            os.fchmod(stream.fileno(), 0o600 if private else stat.S_IMODE(metadata.st_mode))
            os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
            if not private:
                for name in os.listxattr(HOSTS):
                    os.setxattr(temporary, name, os.getxattr(HOSTS, name))
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def change(payload):
    if payload.get('confirmed') is not True:
        raise ValueError('Confirm saving or removing this website rule.')
    operation = payload.get('operation')
    if operation not in ('add-website', 'edit-website', 'remove-website'):
        raise ValueError('Unknown website action.')
    value = domain(payload.get('value'))
    descriptor = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'a') as lock:
        metadata = os.fstat(lock.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o022:
            raise ValueError('The website lock file needs administrator review.')
        fcntl.flock(lock, fcntl.LOCK_EX)
        text, names, revision = read()
        if payload.get('expectedWebsite') != revision:
            raise ValueError('Website rules changed. Refresh before saving.')
        old = domain(payload.get('old')) if operation == 'edit-website' else value
        if operation != 'add-website' and old not in names:
            raise ValueError('This website rule was removed. Refresh the list.')
        result = set(names)
        if operation != 'add-website':
            result.remove(old)
        if operation != 'remove-website':
            result.add(value)
        if len(result) > 200:
            raise ValueError('The website list can contain up to 200 names.')
        if BEGIN in text:
            start = text.index(BEGIN); stop = text.index(END) + len(END)
            updated = text[:start] + content(result) + text[stop:]
        else:
            updated = text + ('' if not text or text.endswith('\n') else '\n') + content(result)
        if updated != text:
            # Preserve other hosts entries and keep the previous version locally.
            metadata = HOSTS.stat()
            backup = HOSTS.with_name(HOSTS.name + '.hyprshell-websites.bak')
            if backup.is_symlink():
                raise ValueError('The website backup path needs review before saving.')
            atomic(backup, text, metadata, private=True)
            # Detect non-Hyprshell edits made during backup creation.
            if read()[2] != revision:
                raise ValueError('The system website file changed. Refresh before saving.')
            atomic(HOSTS, updated, metadata)
        return {**status(), 'message': 'Website rule saved. Close existing tabs and restart your browser if the site still opens.' if operation != 'remove-website' else 'Website block removed. Restart your browser if it still uses the old result.'}
