#!/usr/bin/env python3
"""Per-user language/formats/timezone, with explicit system-timezone changes."""
import argparse
from datetime import datetime
import json
import locale
import os
import shlex
import subprocess
import sys
from zoneinfo import ZoneInfo, available_timezones

from backend import lock
from preferences import managed_block, revision, roots, transaction

DEFAULTS = {'version': 1, 'language': '', 'formats': '', 'timezone': ''}
CATEGORIES = ('LC_TIME', 'LC_NUMERIC', 'LC_MONETARY', 'LC_PAPER', 'LC_MEASUREMENT')


def locales():
    result = subprocess.run(['locale', '-a'], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise ValueError('Could not read generated locales. Check your system locale configuration.')
    return sorted(set(result.stdout.splitlines()))


def validate(data):
    if not isinstance(data, dict) or set(data) != set(DEFAULTS) or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Unsupported regional preferences')
    for key in ('language', 'formats'):
        value = data[key]
        if not isinstance(value, str) or len(value) > 100 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@.-' for c in value):
            raise ValueError('Choose a generated locale from the list.')
    if not isinstance(data['timezone'], str) or (data['timezone'] and data['timezone'] not in available_timezones()):
        raise ValueError('Choose an installed timezone.')
    return data


def paths():
    config, _ = roots()
    return config / 'hyprshell/regional.json', config / 'uwsm/env-hyprland'


def saved():
    path, _ = paths()
    return validate(json.loads(path.read_text())) if path.exists() else dict(DEFAULTS)


def variables(data):
    result = {}
    if data['language']:
        result['LANG'] = data['language']
        result['LANGUAGE'] = data['language'].split('.')[0]
    if data['formats']:
        result.update({name: data['formats'] for name in CATEGORIES})
    if data['timezone']:
        result['TZ'] = data['timezone']
    return result


def environment(original, data):
    return managed_block(original, 'regional preferences', ['export ' + key + '=' + shlex.quote(value) for key, value in variables(data).items()])


def preview(data):
    previous = locale.setlocale(locale.LC_ALL)
    try:
        if data['formats']:
            locale.setlocale(locale.LC_TIME, data['formats'])
            locale.setlocale(locale.LC_NUMERIC, data['formats'])
        now = datetime.now(ZoneInfo(data['timezone'])) if data['timezone'] else datetime.now().astimezone()
        return {'date': now.strftime('%x'), 'time': now.strftime('%X'), 'number': locale.format_string('%.2f', 1234567.89, grouping=True), 'zone': now.tzname()}
    except locale.Error:
        return {'date': '', 'time': '', 'number': '', 'zone': '', 'error': 'This format locale is no longer generated. Choose another.'}
    finally:
        locale.setlocale(locale.LC_ALL, previous)


def status():
    data = saved()
    return {'ok': True, 'settings': data, 'locales': locales(), 'timezones': sorted(available_timezones()),
            'revision': revision(paths()), 'preview': preview(data)}


def save(data, expected, restoring=False):
    data = validate(data)
    _, state = roots()
    with lock(state / 'regional.lock'):
        if not restoring and expected != revision(paths()):
            raise ValueError('Regional preferences changed elsewhere. Refresh before applying.')
        active = dict(data); installed = locales(); skipped = []
        for key in ('language', 'formats'):
            if data[key] and data[key] not in installed:
                if not restoring:
                    raise ValueError('This locale is not generated on this machine. Refresh and choose another.')
                active[key] = ''; skipped.append(data[key])
        path, env = paths()
        changes = {env: environment(env.read_text() if env.exists() else '', active)}
        if not restoring:
            changes[path] = json.dumps(data, indent=2) + '\n'
        backup = transaction(changes, 'regional')
        # Do not overwrite a running application's locale; next login is reliable.
        result = {'ok': True, 'message': 'Regional preferences saved. Log out and back in to apply them to the desktop and new applications.', 'backup': backup, 'skipped': skipped}
        if skipped:
            result['message'] += ' Unavailable locales were skipped on this machine.'
        return result


def request(payload):
    if payload.get('operation') == 'status':
        return status()
    if payload.get('operation') == 'save':
        result = save(payload.get('settings'), payload.get('expected'))
        return {**status(), **result}
    if payload.get('operation') == 'preview':
        return {'ok': True, 'preview': preview(validate(payload.get('settings')))}
    if payload.get('operation') == 'system-timezone':
        zone = payload.get('timezone')
        if not isinstance(zone, str) or zone not in available_timezones():
            raise ValueError('Choose an installed timezone.')
        result = subprocess.run(['timedatectl', 'set-timezone', zone], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise ValueError('System timezone was not changed. Complete desktop administrator authentication and retry.')
        return {'ok': True, 'message': 'System timezone changed to ' + zone + '.'}
    raise ValueError('Unknown regional operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json'); parser.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    try:
        result = save(saved(), None, restoring=True) if args.restore else request(json.loads(args.request_json or '{}'))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'Regional settings could not be updated. Try again from your desktop session.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
