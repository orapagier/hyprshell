#!/usr/bin/env python3
"""On-demand NetworkManager controls. No credentials or profiles are exported."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys


def nmcli(arguments, input_text=None):
    try:
        result = subprocess.run(['nmcli', '--wait', '15', *arguments],
                                input=input_text, capture_output=True, text=True, timeout=20,
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


UUID = re.compile(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')


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


def active_hotspot():
    rows = nmcli(['--terse', '--escape', 'yes', '--fields', 'NAME,UUID,TYPE,DEVICE',
                  'connection', 'show', '--active'])
    for line in rows.splitlines():
        values = fields(line)
        if len(values) != 4:
            raise ValueError('Could not read network connections. Refresh and try again.')
        name, ident, kind, device = values
        if kind != '802-11-wireless' or not device or not UUID.fullmatch(ident):
            continue
        args = ['--get-values', '802-11-wireless.mode', 'connection', 'show', ident]
        if nmcli(args).strip() != 'ap':
            continue
        ssid = nmcli(['--get-values', '802-11-wireless.ssid', 'connection', 'show', ident]).strip()
        return {'name': name, 'uuid': ident, 'device': device, 'ssid': ssid}
    return None


def hotspot_status():
    hotspot = active_hotspot()
    devices = nmcli(['--terse', '--fields', 'DEVICE,TYPE,STATE,CONNECTION', 'device', 'status'])
    wifi_device, sources = '', []
    for line in devices.splitlines():
        values = fields(line)
        if len(values) != 4:
            raise ValueError('Could not read network devices. Refresh and try again.')
        device, kind, state, connection = values
        if kind == 'wifi' and not wifi_device:
            wifi_device = device
        if connection and kind in ('ethernet', 'wifi') and connection != (hotspot or {}).get('name'):
            sources.append(connection)
    return {'ok': True, 'hotspot': hotspot, 'wifiDevice': wifi_device,
            'wifiEnabled': nmcli(['--get-values', 'WIFI', 'general']).strip() == 'enabled',
            'sources': sources, 'connectivity': nmcli(['--get-values', 'CONNECTIVITY', 'general']).strip()}


def hotspot_start(payload, password=''):
    ssid = payload.get('ssid', '')
    if not isinstance(ssid, str) or len(ssid.encode('utf-8')) > 32 or any(ord(c) < 32 for c in ssid):
        raise ValueError('Enter a hotspot name of at most 32 UTF-8 bytes, on one line.')
    if password and (not isinstance(password, str) or not 8 <= len(password.encode('utf-8')) <= 63
                     or any(ord(c) < 32 or ord(c) == 127 for c in password)):
        raise ValueError('Enter a password of 8 to 63 printable characters, or leave it empty to generate one.')
    current = hotspot_status()
    if current['hotspot']:
        raise ValueError('A hotspot is already active. Stop it before starting another.')
    if not current['wifiEnabled']:
        raise ValueError('Turn on Wi-Fi before starting a hotspot.')
    if not current['wifiDevice']:
        raise ValueError('No Wi-Fi device is available for a hotspot.')
    if password:
        # nmcli --ask reads the secret from stdin; no password ever enters argv.
        suffix = hashlib.sha256(os.urandom(6)).hexdigest()[:8]
        profile = 'Hotspot-' + suffix
        output = nmcli(['connection', 'add', 'type', 'wifi', 'con-name', profile,
                        'ifname', current['wifiDevice'], 'ssid', ssid or profile,
                        '802-11-wireless.mode', 'ap', '802-11-wireless.band', 'bg',
                        '802-11-wireless-security.key-mgmt', 'wpa-psk',
                        '802-11-wireless-security.proto', 'rsn',
                        '802-11-wireless-security.pairwise', 'ccmp',
                        '802-11-wireless-security.group', 'ccmp',
                        'connection.autoconnect', 'no', 'ipv4.method', 'shared',
                        'ipv6.method', 'ignore'])
        match = UUID.search(output)
        if not match:
            raise ValueError('Could not create the hotspot profile. Refresh and try again.')
        try:
            nmcli(['--ask', 'connection', 'up', 'uuid', match.group(0)], input_text=password)
        except ValueError:
            try:
                nmcli(['connection', 'delete', 'uuid', match.group(0)])
            except ValueError:
                pass
            raise
        output = ''
    else:
        args = ['device', 'wifi', 'hotspot', 'ifname', current['wifiDevice']]
        if ssid:
            args += ['ssid', ssid]
        output = nmcli(args).strip()
    try:
        state = hotspot_status()
    except ValueError:
        state = {'ok': True, 'hotspot': None, 'wifiDevice': current['wifiDevice'],
                 'wifiEnabled': current['wifiEnabled'], 'sources': current['sources'], 'connectivity': ''}
    # nmcli may echo a supplied password; never send it back to the menu.
    message = 'Hotspot started with the password you entered.' if password else output or 'Hotspot started.'
    return {**state, 'ok': True, 'message': message}


def hotspot_stop(payload):
    ident = payload.get('uuid')
    if not isinstance(ident, str) or not UUID.fullmatch(ident):
        raise ValueError('Refresh the hotspot status before stopping it.')
    current = hotspot_status()
    if not current['hotspot'] or current['hotspot']['uuid'] != ident:
        raise ValueError('The hotspot already stopped. Refresh to check the current state.')
    nmcli(['connection', 'down', 'uuid', ident])
    try:
        state = hotspot_status()
    except ValueError:
        state = {'ok': True, 'hotspot': None, 'wifiDevice': current['wifiDevice'],
                 'wifiEnabled': current['wifiEnabled'], 'sources': current['sources'], 'connectivity': ''}
    return {**state, 'ok': True, 'message': 'Hotspot stopped. Its saved profile was kept.'}


def selected(payload):
    ident = payload.get('uuid')
    if not isinstance(ident, str) or not UUID.fullmatch(ident):
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


def request(payload, password=''):
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
    if operation == 'hotspot-status':
        return hotspot_status()
    if operation == 'hotspot-start':
        return hotspot_start(payload, password)
    if operation == 'hotspot-stop':
        return hotspot_stop(payload)
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
        payload = json.loads(args.request_json)
        password = ''
        if isinstance(payload, dict) and payload.get('operation') == 'hotspot-start' and payload.get('passwordViaStdin') is True:
            password = sys.stdin.readline(256).rstrip('\r\n')
            if not password:
                raise ValueError('Enter a password or leave the field empty to generate one.')
        result = request(payload, password)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        message = str(error) if isinstance(error, ValueError) else 'Could not open the network tool. Try again from your desktop session.'
        result = {'ok': False, 'message': message}
    print(json.dumps(result))


if __name__ == '__main__':
    main()
