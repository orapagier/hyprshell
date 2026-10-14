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
            raise ValueError('The firewall is stopped. Choose Turn on firewall, then Check again.')
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
        active_zones = [line.strip() for line in active.splitlines() if line and not line[0].isspace()]
        zone = active_zones[0] if len(active_zones) == 1 else command(['--get-default-zone'])
    if not token(zone) or zone not in zones:
        raise ValueError('Choose an existing firewall zone and Refresh.')
    return zone, scope, zones


def request(payload):
    if not isinstance(payload, dict):
        raise ValueError('Invalid firewall request.')
    operation = payload.get('operation')
    if operation == 'enable':
        if payload.get('confirmed') is not True:
            raise ValueError('Confirm enabling firewalld first.')
        if not shutil.which('kitty'):
            raise ValueError('Kitty is needed for administrator authentication.')
        result = subprocess.run(['kitty', '--detach', '--hold', '--title', 'Enable firewall',
                                 'sudo', 'systemctl', 'enable', '--now', 'firewalld.service'],
                                capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError('Could not open the administrator terminal.')
        return {'ok': True, 'message': 'Complete authentication in the terminal, then Refresh to verify firewalld.'}
    if operation not in ('status', 'add-service', 'remove-service', 'add-port', 'remove-port', 'block-source', 'remove-rich'):
        raise ValueError('Unknown firewall operation.')
    zone, scope, zones = context(payload)
    current = snapshot(zone, scope)
    if operation == 'status':
        return {'ok': True, 'zone': zone, 'scope': scope, 'zones': zones,
                'active': command(['--get-active-zones']), 'catalog': command(['--get-services']).split(),
                **current}
    if payload.get('confirmed') is not True:
        raise ValueError('Review and confirm this firewall change first.')
    if current['revision'] != payload.get('expected'):
        raise ValueError('Firewall rules changed. Refresh and review before applying.')
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
            raise ValueError('Enter an IPv4/IPv6 address or CIDR network.') from None
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--request-json', required=True)
    args = parser.parse_args()
    try:
        result = request(json.loads(args.request_json))
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'Firewall tool unavailable. Refresh from your desktop session.'}
    print(json.dumps(result))


if __name__ == '__main__':
    main()
