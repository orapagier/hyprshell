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
import website_dns

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


def content(domains, legacy=False):
    if not domains:
        return ''
    lines = [BEGIN]
    for name in sorted(domains):
        include = domains.get(name, False) if isinstance(domains, dict) else False
        annotation = '' if legacy else ' subdomains=' + ('on' if include else 'off')
        lines += ['# website: ' + name + annotation + '\n', '0.0.0.0 ' + name + ' www.' + name + '\n',
                  ':: ' + name + ' www.' + name + '\n']
    return ''.join(lines) + END


def read():
    if HOSTS.is_symlink() or not stat.S_ISREG(HOSTS.stat().st_mode) or HOSTS.stat().st_size > 1048576:
        raise ValueError('The system website file cannot be safely edited here.')
    text = HOSTS.read_text(encoding='utf-8')
    names = {}
    if BEGIN in text or END in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ValueError('The saved website block list needs repair before editing.')
        start = text.index(BEGIN); stop = text.index(END) + len(END)
        if stop <= start:
            raise ValueError('The saved website block list needs repair before editing.')
        if start and text[start - 1] != '\n':
            raise ValueError('The saved website block marker is malformed.')
        block = text[start:stop]
        entries = [line[len('# website: '):] for line in block.splitlines() if line.startswith('# website: ')]
        legacy = all(' subdomains=' not in entry for entry in entries)
        for entry in entries:
            pieces = entry.split(' subdomains=')
            if len(pieces) > 2 or (len(pieces) == 2 and pieces[1] not in ('on', 'off')):
                raise ValueError('The saved website block options need repair.')
            name = domain(pieces[0])
            if name in names: raise ValueError('Duplicate website blocks need review.')
            names[name] = len(pieces) == 2 and pieces[1] == 'on'
        if content(names, legacy=legacy) != block:
            raise ValueError('The saved website block list was manually changed. Review it before editing here.')
    return text, names, hashlib.sha256(text.encode()).hexdigest()


def status():
    _, names, revision = read()
    dns = website_dns.status()
    revision = hashlib.sha256((revision + dns['dnsFilterRevision']).encode()).hexdigest()
    return {**dns, 'websiteRevision': revision, 'websites': [
        {'id': 'website-' + hashlib.sha256(name.encode()).hexdigest()[:16], 'kind': 'website',
         'value': name, 'raw': name, 'title': 'Website: ' + name,
         'subdomains': names[name], 'now': not names[name] or dns['dnsFilterReady'], 'saved': True, 'editable': True} for name in names]}


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


def lock_file():
    descriptor = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    stream = os.fdopen(descriptor, 'a')
    metadata = os.fstat(stream.fileno())
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o022:
        stream.close()
        raise ValueError('The website lock file needs administrator review.')
    fcntl.flock(stream, fcntl.LOCK_EX)
    return stream


def dns_change(operation, payload=None):
    with lock_file():
        if operation == 'setup-website-dns':
            website_dns.setup(read()[1])
        elif operation == 'restore-website-dns':
            website_dns.restore()
        elif operation == 'configure-website-dns':
            if payload.get('expectedWebsite') != status()['websiteRevision']:
                raise ValueError('DNS or website rules changed. Refresh before applying.')
            website_dns.configure(read()[1], payload.get('mode'), payload.get('servers'))
        else:
            raise ValueError('Unknown DNS setup action.')


def change(payload):
    if payload.get('confirmed') is not True:
        raise ValueError('Confirm saving or removing this website rule.')
    operation = payload.get('operation')
    if operation not in ('add-website', 'edit-website', 'remove-website'):
        raise ValueError('Unknown website action.')
    value = domain(payload.get('value'))
    include = payload.get('subdomains', True)
    if type(include) is not bool: raise ValueError('Choose whether to block all subdomains.')
    with lock_file():
        text, names, revision = read()
        if payload.get('expectedWebsite') != status()['websiteRevision']:
            raise ValueError('Website rules changed. Refresh before saving.')
        old = domain(payload.get('old')) if operation == 'edit-website' else value
        if operation != 'add-website' and old not in names:
            raise ValueError('This website rule was removed. Refresh the list.')
        result = dict(names)
        if operation != 'add-website':
            result.pop(old)
        if operation != 'remove-website':
            result[value] = include
        if operation != 'remove-website' and include and not website_dns.status()['dnsFilterReady']:
            raise ValueError('Set up the DNS filter before saving all-subdomain blocks.')
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
        try:
            website_dns.apply(result)
        except (ValueError, OSError) as error:
            if updated != text:
                try: atomic(HOSTS, text, HOSTS.stat())
                except OSError: raise ValueError('Website update and hosts rollback failed. Administrator review is needed.') from error
            raise
        return {**status(), 'message': 'Website rule saved. Close existing tabs and restart your browser if the site still opens.' if operation != 'remove-website' else 'Website block removed. Restart your browser if it still uses the old result.'}
