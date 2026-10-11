#!/usr/bin/env python3
"""On-demand NetworkManager controls. No credentials or profiles are exported."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess


def nmcli(arguments):
    try:
        result = subprocess.run(['nmcli', '--wait', '15', *arguments],
                                capture_output=True, text=True, timeout=20,
                                env=dict(os.environ, LC_ALL='C'))
    except FileNotFoundError:
        raise ValueError('NetworkManager is missing. Install the desktop networking dependencies.') from None
    except subprocess.TimeoutExpired:
        raise ValueError('NetworkManager did not respond in time. Refresh and try again.') from None
    if result.returncode:
        error = result.stderr.lower()
        if 'not permitted' in error or 'not authorized' in error or 'permission' in error:
            raise ValueError('NetworkManager access was denied. Try from your desktop session and check the authorization agent.')
        if 'not running' in error or 'could not connect' in error or 'nmclient' in error:
            raise ValueError('Cannot reach NetworkManager. Check that the service is running in your desktop session.')
        raise ValueError('The network operation failed. Refresh; use Edit for connection settings or Connect for authentication details.')
    return result.stdout


def fields(line):
    """Split nmcli terse output without losing escaped colons or backslashes."""
    result, value, escaped = [], '', False
    for character in line:
        if escaped:
            value += character
            escaped = False
        elif character == '\\':
            escaped = True
        elif character == ':':
            result.append(value)
            value = ''
        else:
            value += character
    if escaped:
        raise ValueError('Could not read network connections. Refresh and try again.')
    return result + [value]


def profiles():
    rows = nmcli(['--terse', '--escape', 'yes', '--fields', 'NAME,UUID,TYPE', 'connection', 'show'])
    active = set(nmcli(['--terse', '--fields', 'UUID', 'connection', 'show', '--active']).splitlines())
    result = []
    for line in rows.splitlines():
        values = fields(line)
        if len(values) != 3:
            raise ValueError('Could not read network connections. Refresh and try again.')
        name, ident, kind = values
        row = {'name': name, 'uuid': ident, 'type': kind, 'active': ident in active}
        row['revision'] = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
        result.append(row)
    return sorted(result, key=lambda row: (not row['active'], row['name'].casefold(), row['uuid']))


def status():
    connections = profiles()
    connectivity = nmcli(['--terse', 'networking', 'connectivity']).strip()
    return {'ok': True, 'profiles': connections, 'connectivity': connectivity,
            'editor': bool(shutil.which('nm-connection-editor'))}


def selected(payload):
    ident = payload.get('uuid')
    if not isinstance(ident, str) or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', ident):
        raise ValueError('Choose a saved connection from the list.')
    row = next((row for row in profiles() if row['uuid'] == ident), None)
    if row is None or row['revision'] != payload.get('expected'):
        raise ValueError('This connection changed or was removed. Refresh before trying again.')
    return row


def editor(arguments):
    if not shutil.which('nm-connection-editor'):
        raise ValueError('Install nm-connection-editor to edit or add network connections.')
    # The editor owns authentication and secret storage, and survives Settings.
    subprocess.Popen(['nm-connection-editor', *arguments], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def connect_terminal(arguments):
    if not shutil.which('kitty'):
        raise ValueError('Kitty is required to open network authentication.')
    result = subprocess.run(['kitty', '--detach', '--hold', '--title', 'Hyprshell network connection',
                             'nmcli', '--ask', '--wait', '60', *arguments],
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError('Could not open the connection terminal. Try from your desktop session.')
    return {'ok': True, 'message': 'Connection terminal opened. Complete authentication there, then Refresh to check the result.'}


def request(payload):
    if not isinstance(payload, dict):
        raise ValueError('Invalid network request.')
    operation = payload.get('operation')
    if operation == 'status':
        return status()
    if operation == 'hidden':
        ssid = payload.get('ssid')
        if not isinstance(ssid, str) or not 1 <= len(ssid.encode('utf-8')) <= 32 or any(c in ssid for c in '\r\n\0'):
            raise ValueError('Enter the exact network name, between 1 and 32 UTF-8 bytes, on one line.')
        return connect_terminal(['device', 'wifi', 'connect', ssid, 'hidden', 'yes'])
    if operation in ('edit', 'connect', 'disconnect', 'forget'):
        row = selected(payload)
        if operation == 'edit':
            editor(['--edit=' + row['uuid']])
            message = 'Opening the connection editor. Refresh after saving.'
        elif operation == 'connect':
            # Keep passwords out of QML, process arguments, logs and Git sync.
            return connect_terminal(['connection', 'up', 'uuid', row['uuid']])
        elif operation == 'disconnect':
            if not row['active']:
                raise ValueError('This connection is already disconnected. Refresh the list.')
            nmcli(['connection', 'down', 'uuid', row['uuid']])
            message = 'Connection deactivated. Networks with automatic connection enabled may reconnect.'
        else:
            if payload.get('confirmed') is not True:
                raise ValueError('Confirm forgetting this connection first.')
            if row['active']:
                raise ValueError('Disconnect this connection before forgetting it.')
            nmcli(['connection', 'delete', 'uuid', row['uuid']])
            message = 'Saved connection removed.'
        if operation in ('disconnect', 'forget'):
            try:
                return {**status(), 'message': message}
            except ValueError:
                return {'ok': True, 'message': message + ' Refresh to reload network status.'}
        return {'ok': True, 'message': message}
    if operation == 'create':
        kind = payload.get('type')
        if kind not in ('802-11-wireless', '802-3-ethernet', 'vpn', 'wireguard'):
            raise ValueError('Choose Wi-Fi, Ethernet, VPN, or WireGuard.')
        editor(['--create', '--type=' + kind])
        return {'ok': True, 'message': 'Opening the connection editor. Save there, then Refresh here.'}
    if operation == 'editor':
        editor([])
        return {'ok': True, 'message': 'Opening advanced connection settings. Refresh after saving.'}
    raise ValueError('Unknown network operation.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--request-json', required=True)
    args = parser.parse_args()
    try:
        result = request(json.loads(args.request_json))
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        message = str(error) if isinstance(error, ValueError) else 'Could not open the network tool. Try again from your desktop session.'
        result = {'ok': False, 'message': message}
    print(json.dumps(result))


if __name__ == '__main__':
    main()
