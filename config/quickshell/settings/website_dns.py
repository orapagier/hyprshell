#!/usr/bin/env python3
"""Optional NetworkManager dnsmasq filter upstream of the existing resolved stub."""
import configparser
import hashlib
import json
import ipaddress
import re
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time

NM = Path('/etc/NetworkManager/conf.d/90-hyprshell-website-dns.conf')
RESOLVED = Path('/etc/systemd/resolved.conf.d/90-hyprshell-website-dns.conf')
RULES = Path('/etc/NetworkManager/dnsmasq.d/90-hyprshell-website-blocks.conf')
STATE = Path('/var/lib/hyprshell/website-dns')
RESOLV = Path('/etc/resolv.conf')
FILTER_RESOLV = '/run/NetworkManager/resolv.conf'
NM_CONTENT = '[main]\ndns=dnsmasq\nsystemd-resolved=false\nrc-manager=symlink\n'
RESOLVED_CONTENT = '[Resolve]\nFallbackDNS=\n'

PRESETS = {
    'malicious': ['1.1.1.2', '1.0.0.2', '2606:4700:4700::1112', '2606:4700:4700::1002'],
    'family': ['1.1.1.3', '1.0.0.3', '2606:4700:4700::1113', '2606:4700:4700::1003'],
}


def selection(mode, servers=None):
    if not isinstance(mode, str):
        raise ValueError('Choose a DNS mode.')
    if mode in PRESETS:
        return mode, list(PRESETS[mode])
    if mode == 'automatic':
        return mode, []
    if mode != 'custom':
        raise ValueError('Choose Automatic, Custom, malicious-site or adult-site protection.')
    if isinstance(servers, str):
        servers = re.split(r'[\s,;]+', servers.strip())
    if not isinstance(servers, list) or not 1 <= len(servers) <= 8:
        raise ValueError('Enter one to eight DNS server IP addresses.')
    result = []
    for value in servers:
        try:
            if not isinstance(value, str) or '%' in value: raise ValueError()
            address = ipaddress.ip_address(value)
        except ValueError:
            raise ValueError('Use numeric IPv4 or IPv6 DNS addresses, without ports or links.') from None
        if address.is_loopback or address.is_unspecified or address.is_multicast or address.is_link_local or str(address) == '255.255.255.255' or (address.version == 6 and address.ipv4_mapped):
            raise ValueError('Use a reachable DNS server address outside the local resolver.')
        if str(address) not in result: result.append(str(address))
    return mode, result


def nm_content(mode='automatic', servers=None):
    mode, servers = selection(mode, servers)
    # Global domains replace connection DNS, including DHCP/IPv6 and VPN
    # routing domains. dnsmasq snippets alone would leave NM's servers active.
    return NM_CONTENT + ('\n[global-dns]\n\n[global-dns-domain-*]\nservers=' + ','.join(servers) + '\n' if servers else '')


def verify_configuration(mode, servers):
    config = configparser.ConfigParser(strict=False, interpolation=None)
    config.read_string(command(['NetworkManager', '--print-config']))
    if (config.get('main', 'dns', fallback='') != 'dnsmasq'
            or config.get('main', 'systemd-resolved', fallback='true') not in ('false', 'no', '0')
            or config.get('main', 'rc-manager', fallback='') != 'symlink'):
        raise ValueError('Another NetworkManager setting overrides the DNS filter.')
    domains = [section for section in config.sections() if section.startswith('global-dns-domain-')]
    if mode == 'automatic':
        if any(section.startswith('global-dns') for section in config.sections()):
            raise ValueError('Another global DNS setting overrides Automatic mode.')
    else:
        actual = config.get('global-dns-domain-*', 'servers', fallback='')
        if domains != ['global-dns-domain-*'] or re.split(r'[\s,;]+', actual.strip()) != servers:
            raise ValueError('Another global DNS setting overrides the selected servers.')


def command(args, timeout=30):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                            env=dict(os.environ, LC_ALL='C'))
    if result.returncode:
        action = args[0].rsplit('/', 1)[-1]
        if action == 'nmcli' and args[1:3] == ['general', 'reload']: action = 'NetworkManager DNS reload'
        elif action == 'systemctl': action = 'systemd-resolved service update'
        raise ValueError(action + ' failed (exit ' + str(result.returncode) + ').')
    return result.stdout


def describe(error):
    if isinstance(error, ValueError): return str(error)
    if isinstance(error, subprocess.TimeoutExpired): return 'The system command timed out.'
    if isinstance(error, OSError): return 'System operation failed (errno ' + str(error.errno) + ').'
    return 'The system operation failed.'


def generated(domains):
    # With no server address dnsmasq returns NXDOMAIN for every RR type,
    # including A, AAAA and HTTPS, across the complete suffix.
    return '# Managed by Hyprshell website blocks\n' + ''.join('local=/' + name + '/\n' for name, include in sorted(domains.items()) if include)


def replace(path, text, mode=0o644):
    if path.is_symlink():
        raise ValueError('A DNS filter path is a symlink. Review it before continuing.')
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.hyprshell-dns-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text); stream.flush(); os.fchmod(stream.fileno(), mode)
            if path.exists():
                metadata = path.stat(); os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
                for name in os.listxattr(path): os.setxattr(temporary, name, os.getxattr(path, name))
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        # Newly created /etc files need their normal Fedora SELinux labels.
        restorecon = shutil.which('restorecon')
        if restorecon: command([restorecon, str(path)])
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def link_resolver(target):
    descriptor, temporary = tempfile.mkstemp(prefix='.hyprshell-resolv-', dir=RESOLV.parent)
    os.close(descriptor); os.unlink(temporary)
    try:
        os.symlink(target, temporary); os.replace(temporary, RESOLV)
        restorecon = shutil.which('restorecon')
        if restorecon: command([restorecon, str(RESOLV)])
    finally:
        if os.path.lexists(temporary): os.unlink(temporary)


def status():
    receipt = STATE / 'installed.json'
    installed = receipt.is_file() and not receipt.is_symlink()
    record = json.loads(receipt.read_text()) if installed else {}
    phase = record.get('phase', '')
    ready = (installed and phase == 'installed' and not receipt.is_symlink() and shutil.which('dnsmasq') is not None
             and NM.is_file() and not NM.is_symlink() and NM.read_text() == nm_content(record.get('mode', 'automatic'), record.get('servers', []))
             and RESOLVED.is_file() and not RESOLVED.is_symlink() and RESOLVED.read_text() == RESOLVED_CONTENT
             and RESOLV.is_symlink() and str(RESOLV.readlink()) == FILTER_RESOLV
             and RULES.is_file() and not RULES.is_symlink()
             and record.get('rulesHash') == hashlib.sha256(RULES.read_bytes()).hexdigest())
    digest = hashlib.sha256(((RULES.read_text() + NM.read_text()) if ready else '').encode()).hexdigest()
    return {'dnsFilterReady': bool(ready), 'dnsFilterInstalled': installed, 'dnsFilterRevision': digest,
            'dnsMode': record.get('mode', 'automatic'), 'dnsServers': record.get('servers', [])}


def probe(name, server='127.0.0.1'):
    ident = os.urandom(2)
    query = ident + struct.pack('!HHHHH', 0x0100, 1, 0, 0, 0)
    query += b''.join(bytes([len(label)]) + label.encode('ascii') for label in name.split('.')) + b'\0' + struct.pack('!HH', 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(5); client.connect((server, 53)); client.send(query)
        response = client.recv(4096)
    if len(response) < 12 or response[:2] != ident or not response[2] & 0x80:
        raise ValueError('The DNS filter did not return a valid response.')
    return response[3] & 15


def reload():
    # nmcli accepts ONE comma-separated flags argument.
    update = ['nmcli', 'general', 'reload', 'conf,dns-full']
    restart = ['systemctl', 'restart', 'systemd-resolved.service']
    filtering = NM.is_file() and NM.read_text().startswith(NM_CONTENT)
    if filtering:
        command(update)
        # Clear old direct per-link servers after disabling their NM updates.
        command(restart)
    else:
        # Restore first, then let NM supply fresh per-link DNS to the new instance.
        command(restart)
        command(update)


def validate(text):
    tool = shutil.which('dnsmasq')
    if not tool: raise ValueError('Set up the DNS filter before blocking all subdomains.')
    with tempfile.NamedTemporaryFile(mode='w', prefix='hyprshell-dns-', suffix='.conf') as stream:
        stream.write(text); stream.flush()
        command([tool, '--test', '--conf-file=' + stream.name])


def verify_once(domains):
    for name, include in domains.items():
        if include:
            available = 253 - len(name) - 1
            if available < 1: continue
            child = ('hyprshell-check-' + os.urandom(4).hex())[:available] + '.' + name
            if probe(child) != 3 or probe(child, '127.0.0.53') != 3:
                raise ValueError('The subdomain block could not be verified through the DNS filter and system resolver.')
    # Both the filter and system resolver must respond on an unrelated name.
    check = next((name for name in ('example.com', 'example.net', 'example.org')
                  if not any(name == base or name.endswith('.' + base) for base, include in domains.items() if include)), None)
    if check and (probe(check) != 0 or probe(check, '127.0.0.53') != 0):
        raise ValueError('Normal DNS lookup could not be verified. Previous DNS settings will be restored.')


def verify(domains):
    deadline = time.monotonic() + 12
    while True:
        try:
            verify_once(domains)
            return
        except (ValueError, OSError):
            if time.monotonic() >= deadline: raise
            time.sleep(0.3)


def apply(domains):
    if not status()['dnsFilterReady']:
        return
    text = generated(domains)
    validate(text)
    old = RULES.read_text()
    old_receipt = (STATE / 'installed.json').read_text()
    record = json.loads(old_receipt)
    verify_configuration(record.get('mode', 'automatic'), record.get('servers', []))
    if old == text: return
    try:
        replace(RULES, text); reload(); verify(domains)
        record = json.loads(old_receipt); record['rulesHash'] = hashlib.sha256(text.encode()).hexdigest()
        replace(STATE / 'installed.json', json.dumps(record), mode=0o600)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        try:
            replace(RULES, old); replace(STATE / 'installed.json', old_receipt, mode=0o600); reload()
        except (ValueError, OSError, subprocess.TimeoutExpired):
            raise ValueError('DNS rule update and rollback failed. Use Restore DNS setup before retrying.') from error
        raise ValueError('DNS rule update failed; the previous filter rules were restored.') from error


def preflight():
    if not RESOLV.is_symlink() or not str(RESOLV.resolve()).endswith('/run/systemd/resolve/stub-resolv.conf'):
        raise ValueError('Automatic setup requires the existing systemd-resolved stub. Your DNS setup needs manual review.')
    command(['systemctl', 'is-active', 'NetworkManager.service'])
    command(['systemctl', 'is-active', 'systemd-resolved.service'])
    # Refuse managed-path collisions and preserve custom DNS/security policies.
    for path in (NM, RESOLVED, RULES):
        if path.exists() or path.is_symlink():
            raise ValueError('A DNS filter file already exists without an installation record. Review it before setup.')
    if any(path != RULES for path in RULES.parent.glob('*.conf')):
        raise ValueError('Existing dnsmasq snippets need review before enabling the filter.')
    resolved = command(['systemd-analyze', 'cat-config', 'systemd/resolved.conf'])
    settings = {}
    group = ''
    for raw in resolved.splitlines():
        line = raw.strip()
        if line.startswith('['): group = line
        elif group == '[Resolve]' and '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1); settings[key.strip()] = value.strip()
    if any(key in settings for key in ('DNS', 'Domains')) or settings.get('FallbackDNS') or settings.get('DNSOverTLS', 'no') not in ('', 'no', 'false') or settings.get('DNSSEC', 'no') not in ('', 'no', 'false', 'allow-downgrade'):
        raise ValueError('Custom DNS or strict DNS security settings were found. Automatic filter setup needs review before changing them.')
    for line in command(['ss', '--no-header', '--listening', '--numeric', '--udp', '( sport = :53 )']).splitlines():
        if any(endpoint in line.split() for endpoint in ('127.0.0.1:53', '0.0.0.0:53', '*:53', '[::]:53')):
            raise ValueError('Another local DNS server uses the filter address. Automatic setup needs review.')
    for ident in command(['nmcli', '--terse', '--fields', 'UUID', 'connection', 'show', '--active']).splitlines():
        # Read only the DNS security setting, never profile secrets.
        value = command(['nmcli', '--get-values', 'connection.dns-over-tls', 'connection', 'show', ident]).strip().split(' ')[0]
        if value not in ('', '-1', '0', 'no', 'default'):
            raise ValueError('An active connection has custom DNS-over-TLS settings. Automatic filter setup needs review.')
    config = configparser.ConfigParser(strict=False, interpolation=None)
    config.read_string(command(['NetworkManager', '--print-config']))
    if any(section.startswith('global-dns') for section in config.sections()):
        raise ValueError('Existing global DNS settings need review before filter setup.')
    mode = config.get('main', 'dns', fallback='systemd-resolved')
    tls = config.get('connection', 'connection.dns-over-tls', fallback='no')
    if tls not in ('', 'no', 'false', '0', '-1', 'default'):
        raise ValueError('Custom connection DNS-over-TLS defaults need review before filter setup.')
    if mode not in ('default', 'systemd-resolved'):
        raise ValueError('Another DNS provider owns networking. Automatic setup will not replace it.')


def setup(domains, mode='automatic', servers=None):
    mode, servers = selection(mode, servers)
    if status()['dnsFilterReady']:
        apply(domains); return status()
    if (STATE / 'installed.json').exists():
        raise ValueError('An earlier DNS setup needs restoration before retrying.')
    preflight()
    if not shutil.which('dnsmasq'):
        release = Path('/etc/os-release').read_text()
        if '\nID=fedora\n' not in '\n' + release:
            raise ValueError('Install dnsmasq with your system package manager, then run Set up DNS filter again.')
        command(['dnf', '-y', 'install', 'dnsmasq'], timeout=300)
    validate(generated(domains))
    STATE.mkdir(parents=True, exist_ok=True); STATE.chmod(0o700)
    # Setup creates only these three managed snippets. Original files, services,
    # connection profiles and nsswitch.conf remain in place; resolver link is recorded.
    original_link = str(RESOLV.readlink())
    replace(STATE / 'installed.json', json.dumps({'version': 1, 'phase': 'preparing', 'rulesHash': hashlib.sha256(generated(domains).encode()).hexdigest(), 'originalResolvLink': str(RESOLV.readlink()), 'mode': mode, 'servers': servers}), mode=0o600)
    try:
        replace(RULES, generated(domains)); replace(NM, nm_content(mode, servers)); replace(RESOLVED, RESOLVED_CONTENT)
        verify_configuration(mode, servers)
        link_resolver(FILTER_RESOLV); reload(); verify(domains)
        replace(STATE / 'installed.json', json.dumps({'version': 1, 'phase': 'installed', 'rulesHash': hashlib.sha256(generated(domains).encode()).hexdigest(), 'originalResolvLink': original_link, 'mode': mode, 'servers': servers}), mode=0o600)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        try:
            for path in (NM, RESOLVED, RULES): path.unlink(missing_ok=True)
            link_resolver(original_link); reload()
        except (ValueError, OSError, subprocess.TimeoutExpired) as recovery:
            raise ValueError('DNS setup failed: ' + describe(error) + ' Recovery failed: ' + describe(recovery) + ' Use Restore DNS setup.') from error
        (STATE / 'installed.json').unlink(missing_ok=True)
        raise ValueError('DNS setup failed: ' + describe(error) + ' Original DNS configuration was restored. Check your connection and retry.') from error
    return status()


def restore():
    if not (STATE / 'installed.json').is_file():
        raise ValueError('No completed Hyprshell DNS setup is recorded.')
    record = json.loads((STATE / 'installed.json').read_text())
    expected_nm = [nm_content(record.get('mode', 'automatic'), record.get('servers', []))]
    if record.get('phase') == 'changing':
        expected_nm.append(nm_content(record.get('previousMode', 'automatic'), record.get('previousServers', [])))
    for path, expected in ((NM, expected_nm), (RESOLVED, [RESOLVED_CONTENT])):
        if path.is_symlink() or (path.exists() and path.read_text() not in expected):
            raise ValueError('Managed DNS files were changed. Restoration needs administrator review.')
    record = json.loads((STATE / 'installed.json').read_text())
    original_link = record.get('originalResolvLink')
    if not isinstance(original_link, str) or not RESOLV.is_symlink() or str(RESOLV.readlink()) not in (FILTER_RESOLV, original_link):
        raise ValueError('The resolver link was changed. Restoration needs administrator review.')
    if RULES.is_symlink() or (RULES.exists() and hashlib.sha256(RULES.read_bytes()).hexdigest() != record.get('rulesHash')):
        raise ValueError('Managed DNS rules were changed. Restoration needs administrator review.')
    contents = {path: path.read_text() for path in (NM, RESOLVED, RULES) if path.exists()}
    try:
        for path in contents: path.unlink()
        link_resolver(original_link); reload()
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        for path, text in contents.items(): replace(path, text)
        link_resolver(FILTER_RESOLV); reload()
        raise ValueError('DNS restoration failed; the filter setup was reinstated.') from error
    (STATE / 'installed.json').unlink()
    return status()


def configure(domains, mode, servers=None):
    mode, servers = selection(mode, servers)
    current = status()
    if not current['dnsFilterInstalled']:
        if mode == 'automatic': return current
        return setup(domains, mode, servers)
    if not current['dnsFilterReady']:
        raise ValueError('Restore the incomplete DNS setup before changing DNS mode.')
    old = NM.read_text()
    text = nm_content(mode, servers)
    if old == text:
        verify_configuration(mode, servers)
        return current
    receipt = STATE / 'installed.json'
    old_receipt = receipt.read_text()
    try:
        record = json.loads(old_receipt)
        record.update(phase='changing', previousMode=record.get('mode', 'automatic'), previousServers=record.get('servers', []), mode=mode, servers=servers)
        replace(receipt, json.dumps(record), mode=0o600)
        replace(NM, text); verify_configuration(mode, servers); reload(); verify(domains)
        record.update(phase='installed')
        record.pop('previousMode'); record.pop('previousServers')
        replace(receipt, json.dumps(record), mode=0o600)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        try:
            replace(NM, old); replace(receipt, old_receipt, mode=0o600); reload()
        except (ValueError, OSError, subprocess.TimeoutExpired) as recovery:
            raise ValueError('DNS change and rollback failed. Use Restore DNS setup.') from recovery
        raise ValueError('DNS change failed: ' + describe(error) + ' Previous DNS mode was restored.') from error
    return status()
