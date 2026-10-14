#!/usr/bin/env python3
"""Manual desktop health checks and redacted, local-only diagnostic reports."""
import argparse
from datetime import datetime, timezone
import json
import os
import platform
import shutil
import subprocess
import sys

import backend
import build_info
from preferences import roots

SERVICES = (
    ('Network connection service', False, 'NetworkManager.service', -15),
    ('Bluetooth service', False, 'bluetooth.service', -15),
    ('Audio playback service', True, 'pipewire.service', -12),
    ('Audio routing service', True, 'wireplumber.service', -12),
    ('Desktop authorization', True, 'hyprpolkitagent.service', -18),
    ('File chooser and screen-sharing portals', True, 'xdg-desktop-portal.service', -13),
)
COMMANDS = ('Hyprland', 'quickshell', 'nmcli', 'nm-connection-editor', 'wpctl', 'hypridle', 'kitty', 'brightnessctl')


def invoke(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=4, env=dict(os.environ, LC_ALL='C'))
        return result.returncode, result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None, ''


def welcome():
    _, state = roots()
    path = state / 'welcome.json'
    try:
        return json.loads(path.read_text()).get('completed') is True
    except (OSError, ValueError, AttributeError):
        return False


def check():
    rows = []
    for label, user, unit, page in SERVICES:
        args = ['systemctl'] + (['--user'] if user else []) + ['show', '--property=ActiveState', '--value', unit]
        code, value = invoke(args)
        if code is None or code != 0 or value not in ('active', 'inactive', 'failed', 'activating', 'deactivating'):
            state, hint = 'unavailable', 'Could not inspect this service from the current session. Check it from your desktop.'
        elif value == 'active':
            state, hint = 'ok', 'Running.'
        elif value == 'failed':
            state, hint = 'attention', 'The service reported a failure. Review its settings or restart the affected application.'
        else:
            state, hint = 'inactive', 'Not currently active. Some desktop services start only when needed.'
        rows.append({'title': label, 'state': state, 'hint': hint, 'page': page})
    missing = [name for name in COMMANDS if not shutil.which(name)]
    rows.append({'title': 'Core desktop tools', 'state': 'attention' if missing else 'ok',
                 'hint': 'Missing: ' + ', '.join(missing) if missing else 'Required tools are available.', 'page': -14})
    try:
        config, _ = roots(); path = config / 'hyprshell/settings.json'
        backend.validate(json.loads(path.read_text()) if path.exists() else backend.DEFAULTS)
        state, hint = 'ok', 'Saved desktop preferences are valid.'
    except (OSError, ValueError, TypeError):
        state, hint = 'attention', 'Saved desktop preferences need review. Use Updates & recovery to inspect a checkpoint.'
    rows.append({'title': 'Saved desktop settings', 'state': state, 'hint': hint, 'page': -14})
    code, errors = invoke(['hyprctl', 'configerrors'])
    state = 'unavailable' if code is None or code != 0 else 'attention' if errors and errors.lower() != 'ok' else 'ok'
    hint = {'unavailable': 'Compositor access is unavailable in this session.', 'attention': 'The compositor reported configuration errors. Review recent changes and your checkpoints.', 'ok': 'The compositor reports no configuration errors.'}[state]
    rows.append({'title': 'Desktop compositor', 'state': state, 'hint': hint, 'page': -2})
    # No hostname, username, IP/SSID, devices, window titles, commands, paths or logs.
    return {'version': 1, 'created': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'system': {'platform': platform.system(), 'kernel': platform.release(), 'architecture': platform.machine(),
                       'hyprshell': build_info.installed()},
            'checks': rows}


def request(payload):
    operation = payload.get('operation')
    if operation == 'status':
        return {'ok': True, 'guideComplete': welcome(), 'build': build_info.installed()}
    if operation == 'guide-complete':
        _, state = roots()
        backend.atomic(state / 'welcome.json', json.dumps({'version': 1, 'completed': True}))
        return {'ok': True, 'guideComplete': True, 'message': 'Getting-started guide completed. You can revisit it here anytime.'}
    if operation in ('check', 'export'):
        report = check()
        result = {'ok': True, 'report': report, 'message': 'Desktop checks finished.'}
        if operation == 'export':
            _, state = roots()
            path = state / 'diagnostics' / ('desktop-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
            path.parent.mkdir(parents=True, mode=0o700)
            backend.atomic(path, json.dumps(report, indent=2) + '\n')
            result.update(path=str(path), message='Diagnostic report saved locally. Review it before sharing.')
        return result
    raise ValueError('Unknown help operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json', required=True); args = parser.parse_args()
    try:
        result = request(json.loads(args.request_json))
    except (ValueError, OSError, TypeError, AttributeError):
        result = {'ok': False, 'message': 'Desktop checks could not finish. Refresh and try again.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
