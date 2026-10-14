#!/usr/bin/env python3
"""Explicit firewalld controls; system rules and addresses never enter config sync."""
import argparse
import hashlib
import ipaddress
import json
import os
import re
import shutil
import subprocess
import website_blocks


class FirewallStopped(ValueError):
    pass


def command(arguments):
    try:
        result = subprocess.run(['firewall-cmd', *arguments], capture_output=True,
                                text=True, timeout=30, env=dict(os.environ, LC_ALL='C'))
    except FileNotFoundError:
        raise ValueError('firewalld is missing. Install firewalld using your system package manager.') from None
    except subprocess.TimeoutExpired:
        raise ValueError('Firewall request timed out. Refresh to check whether it completed.') from None
    if result.returncode:
        error = (result.stderr + result.stdout).lower()
        if 'not_running' in error or 'not running' in error:
            raise FirewallStopped('The firewall is stopped. Choose Turn on firewall, then Check again.')
        if any(term in error for term in ('dbus_error', 'not permitted', 'not authorized', 'authorization', 'permission', 'accessdenied')):
            raise ValueError('Cannot access the firewall. Open Settings in your desktop session and complete any administrator prompt. If access is still denied, the firewall service or password prompt needs checking.')
        raise ValueError('Firewall operation failed. Refresh and check the rule and zone before retrying.')
    return result.stdout.strip()


def token(value):
    return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', value)


def snapshot(zone, scope):
    if scope == 'both':
        current = snapshot(zone, 'runtime')
        saved = snapshot(zone, 'permanent')
        current['saved'] = saved
        current['revision'] = hashlib.sha256((current['revision'] + saved['revision']).encode()).hexdigest()
        return current
    args = ['--zone=' + zone] + (['--permanent'] if scope == 'permanent' else [])
    result = {'details': command([*args, '--list-all']),
              'services': command([*args, '--list-services']).split(),
              'ports': command([*args, '--list-ports']).split(),
              'rich': command([*args, '--list-rich-rules']).splitlines()}
    result['revision'] = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
    return result


def context(payload):
    scope = payload.get('scope', 'runtime')
    if scope not in ('runtime', 'permanent', 'both'):
        raise ValueError('Choose current or saved rules.')
    zones = command((['--permanent'] if scope == 'permanent' else []) + ['--get-zones']).split()
    zone = payload.get('zone')
    if not zone:
        active = command(['--get-active-zones'])
        active_zones = [line.split()[0] for line in active.splitlines() if line and not line[0].isspace()]
        zone = active_zones[0] if len(active_zones) == 1 else command(['--get-default-zone'])
    if not token(zone) or zone not in zones:
        if payload.get('operation') == 'status' and payload.get('zone'):
            return context({'scope': scope})
        raise ValueError('Choose an existing firewall zone and Refresh.')
    return zone, scope, zones


SERVICE_NAMES = {'ssh': 'Remote login (SSH)', 'http': 'Web server (HTTP)',
                 'https': 'Secure web server (HTTPS)', 'samba': 'File sharing (Samba)',
                 'dhcpv6-client': 'IPv6 network setup', 'mdns': 'Device discovery'}


def blocked_address(rule):
    address = re.fullmatch(r'rule (?:family="ipv[46]" priority="-100"|priority="-100" family="ipv[46]") source address="([^"]+)" drop', rule)
    if address:
        try:
            return str(ipaddress.ip_network(address[1], strict=False))
        except ValueError:
            pass
    return None


def rule_rows(current):
    result = []
    saved = current.get('saved', {})
    for key, kind in [('services', 'service'), ('ports', 'port'), ('rich', 'rich')]:
        for value in dict.fromkeys(current.get(key, []) + saved.get(key, [])):
            address = blocked_address(value) if kind == 'rich' else None
            row = {'kind': 'block' if address else kind, 'value': address or value,
                   'raw': value, 'now': value in current.get(key, []), 'saved': value in saved.get(key, []),
                   'editable': kind != 'rich' or bool(address)}
            row['title'] = (SERVICE_NAMES.get(value, value) if kind == 'service' else
                            'Port ' + value.upper() if kind == 'port' else
                            'Blocked address: ' + address if address else 'Advanced rule')
            row['id'] = hashlib.sha256((kind + value).encode()).hexdigest()[:16]
            result.append(row)
    return result


def replacement(kind, value):
    if kind == 'service':
        if not token(value) or value not in command(['--get-services']).split():
            raise ValueError('Choose an available service.')
        return 'service', value
    if kind == 'port':
        match = re.fullmatch(r'([0-9]{1,5})(?:-([0-9]{1,5}))?/(tcp|udp)', value) if isinstance(value, str) else None
        if not match or not 1 <= int(match[1]) <= int(match[2] or match[1]) <= 65535:
            raise ValueError('Enter a port from 1 to 65535 and choose TCP or UDP.')
        return 'port', value
    if kind == 'block':
        try:
            network = ipaddress.ip_network(value, strict=False)
        except (ValueError, TypeError):
            raise ValueError('Enter a valid IP address or network.') from None
        return 'rich-rule', f'rule family="ipv{network.version}" priority="-100" source address="{network}" drop'
    raise ValueError('Choose a service, port or blocked address.')


def edit_rule(payload, zone, scope, current):
    old = next((row for row in rule_rows(current) if row['id'] == payload.get('id')), None)
    if not old or not old['editable']:
        raise ValueError('This rule cannot be edited here. Refresh the rules list.')
    kind = payload.get('kind')
    value = payload.get('value')
    option_kind, new_value = replacement(kind, value)  # Validate before any writes.
    old_option = {'service': 'service', 'port': 'port', 'block': 'rich-rule'}[old['kind']]
    old_key = {'service': 'services', 'port': 'ports', 'block': 'rich'}[old['kind']]
    new_key = {'service': 'services', 'port': 'ports', 'block': 'rich'}[kind]
    completed = []
    try:
        for target in (['permanent', 'runtime'] if scope == 'both' else [scope]):
            view = current['saved'] if scope == 'both' and target == 'permanent' else current
            base = ['--zone=' + zone] + (['--permanent'] if target == 'permanent' else [])
            same = kind == old['kind'] and (value == old['value'] or new_value == old['raw'])
            exists = new_value in view[new_key]
            if kind == 'block':
                exists = any(blocked_address(rule) == str(ipaddress.ip_network(value, strict=False)) for rule in view['rich'])
            if not exists:
                command([*base, '--add-' + option_kind + '=' + new_value])
                completed.append([*base, '--remove-' + option_kind + '=' + new_value])
            if not same and old['raw'] in view[old_key]:
                command([*base, '--remove-' + old_option + '=' + old['raw']])
                completed.append([*base, '--add-' + old_option + '=' + old['raw']])
    except ValueError as error:
        rollback_failed = False
        for undo in reversed(completed):
            try:
                command(undo)
            except ValueError:
                rollback_failed = True
        raise ValueError(('The edit only partly completed. Refresh and review the rules before trying again. ' if rollback_failed else
                          'The edit failed; completed changes were undone. ') + str(error)) from None
    try:
        return {**request({'operation': 'status', 'zone': zone, 'scope': scope}), 'message': 'Rule updated.'}
    except ValueError:
        return {'ok': True, 'message': 'Rule updated. Refresh to see the result.'}


def request_firewall(payload):
    if not isinstance(payload, dict):
        raise ValueError('Invalid firewall request.')
    operation = payload.get('operation')
    if operation in ('enable', 'disable'):
        if payload.get('confirmed') is not True:
            raise ValueError('Confirm turning the firewall on or off first.')
        if os.geteuid() != 0 and not shutil.which('pkexec'):
            raise ValueError('Administrator authentication is unavailable. Install polkit and use a desktop authorization agent.')
        action = 'enable' if operation == 'enable' else 'disable'
        result = subprocess.run([*(['pkexec'] if os.geteuid() != 0 else []), '/usr/bin/systemctl', action, '--now', 'firewalld.service'],
                                capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise ValueError('The firewall switch was not changed. Authentication was cancelled or the system could not complete the request. Refresh to check its status.')
        try:
            return {**request({'operation': 'status', 'scope': 'both'}), 'message': 'Firewall turned ' + ('on.' if operation == 'enable' else 'off. Existing rules are kept.')}
        except ValueError:
            return {'ok': True, 'message': 'The system accepted the change. Refresh to check firewall status.'}
    if operation not in ('status', 'add-service', 'remove-service', 'add-port', 'remove-port', 'block-source', 'remove-rich', 'edit-rule'):
        raise ValueError('Unknown firewall operation.')
    try:
        zone, scope, zones = context(payload)
        current = snapshot(zone, scope)
    except FirewallStopped:
        if operation == 'status':
            return {'ok': True, 'running': False, 'rules': [], 'zones': [], 'catalog': [], 'message': ''}
        raise
    if operation == 'status':
        return {'ok': True, 'running': True, 'rules': rule_rows(current), 'zone': zone, 'scope': scope, 'zones': zones,
                'active': command(['--get-active-zones']), 'catalog': command(['--get-services']).split(),
                **current}
    if payload.get('confirmed') is not True:
        raise ValueError('Review and confirm this firewall change first.')
    if current['revision'] != payload.get('expected'):
        raise ValueError('Firewall rules changed. Refresh and review before applying.')
    if operation == 'edit-rule':
        return edit_rule(payload, zone, scope, current)
    value = payload.get('value')
    if operation.endswith('service'):
        if not token(value) or value not in command(['--get-services']).split():
            raise ValueError('Enter a known service name, such as ssh or http.')
        option = '--' + operation + '=' + value
    elif operation.endswith('port'):
        match = re.fullmatch(r'([0-9]{1,5})(?:-([0-9]{1,5}))?/(tcp|udp)', value) if isinstance(value, str) else None
        if not match or not 1 <= int(match[1]) <= int(match[2] or match[1]) <= 65535:
            raise ValueError('Use a port or range with tcp or udp, such as 8080/tcp or 8000-8010/udp (1–65535).')
        option = '--' + operation + '=' + value
    elif operation == 'block-source':
        try:
            address = ipaddress.ip_network(value, strict=False)
        except (ValueError, TypeError):
            raise ValueError('This option needs a numeric IP address. To block a name such as example.com, choose Block a website.') from None
        rule = f'rule family="ipv{address.version}" priority="-100" source address="{address}" drop'
        option = '--add-rich-rule=' + rule
    else:
        if not isinstance(value, str) or value not in current['rich'] + current.get('saved', {}).get('rich', []):
            raise ValueError('Choose an existing rich rule from the refreshed list.')
        option = '--remove-rich-rule=' + value
    if operation == 'remove-service' and value not in current['services'] + current.get('saved', {}).get('services', []):
        raise ValueError('This service is already absent. Refresh.')
    if operation == 'remove-port' and value not in current['ports'] + current.get('saved', {}).get('ports', []):
        raise ValueError('This port is already absent. Refresh.')
    applied = []
    for target in (['permanent', 'runtime'] if scope == 'both' else [scope]):
        view = current.get('saved', {}) if target == 'permanent' and scope == 'both' else current
        key = {'remove-service': 'services', 'remove-port': 'ports', 'remove-rich': 'rich'}.get(operation)
        if key and value not in view[key]:
            continue
        try:
            command(['--zone=' + zone, *(['--permanent'] if target == 'permanent' else []), option])
        except ValueError as error:
            if applied:
                raise ValueError('The change was saved for future restarts, but could not be applied now. Refresh to check the result and retry. ' + str(error)) from None
            raise
        applied.append(target)
    message = ('Saved rule changed. It takes effect after reload/restart; apply the same change to Current rules for immediate effect.'
               if scope == 'permanent' else 'Current rule changed. It lasts until firewall reload or restart; repeat in Saved rules to retain it.')
    if scope == 'both':
        message = 'Change applied now and saved for future restarts.'
    try:
        return {**request({'operation': 'status', 'zone': zone, 'scope': scope}), 'message': message}
    except ValueError:
        return {'ok': True, 'message': message + ' Refresh to read the result.'}


def request(payload):
    if not isinstance(payload, dict):
        raise ValueError('Invalid firewall request.')
    if payload.get('operation') in ('setup-website-dns', 'restore-website-dns', 'configure-website-dns'):
        if payload.get('confirmed') is not True: raise ValueError('Confirm the DNS setup change first.')
        website_blocks.dns_change(payload['operation'], payload)
        try:
            result = request({'operation': 'status', 'scope': 'both', 'zone': payload.get('zone', '')})
        except ValueError:
            result = {'ok': True, 'firewallUnavailable': True, 'running': False, 'rules': [], **website_blocks.status()}
        return {**result, 'message': 'DNS mode saved and connection checked.' if payload['operation'] == 'configure-website-dns' else 'DNS filter is ready.' if payload['operation'] == 'setup-website-dns' else 'Original DNS setup restored. Exact website blocks remain.'}
    if payload.get('operation') in ('add-website', 'edit-website', 'remove-website'):
        website = website_blocks.change(payload)
        try:
            result = request_firewall({'operation': 'status', 'scope': 'both', 'zone': payload.get('zone', '')})
        except ValueError:
            result = {'ok': True, 'firewallUnavailable': True, 'running': False, 'rules': []}
        return {**result, **website, 'ok': True}
    result = request_firewall(payload)
    try:
        result.update(website_blocks.status())
    except (ValueError, OSError) as error:
        result.update({'websites': [], 'websiteRevision': '', 'websiteError': 'Website rules could not be read. ' + (str(error) if isinstance(error, ValueError) else 'Check access to the system hosts file.')})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--request-json', required=True)
    args = parser.parse_args()
    try:
        result = request(json.loads(args.request_json))
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        message = str(error) if isinstance(error, ValueError) else 'The firewall request could not finish. Refresh to check its status.'
        if isinstance(error, subprocess.TimeoutExpired):
            message = 'The firewall request took too long. Refresh to check whether it completed.'
        result = {'ok': False, 'message': message}
        # An unsuccessful setup can leave a recovery receipt. Return it now,
        # without requiring another Refresh/authentication before showing Restore.
        try: result.update(website_blocks.status())
        except (ValueError, OSError): pass
    print(json.dumps(result))


if __name__ == '__main__':
    main()
