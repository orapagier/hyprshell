#!/usr/bin/env python3
"""Default applications and next-login startup choices; never execute entries."""
import argparse
import configparser
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
from datetime import datetime

from backend import atomic, lock

GROUPS = [
    ('Web browser', ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html']),
    ('Email', ['x-scheme-handler/mailto']),
    ('File manager', ['inode/directory']),
    ('PDF documents', ['application/pdf']),
    ('Office documents (.docx, .doc, .docm, .odt)', [
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/msword', 'application/vnd.ms-word.document.macroEnabled.12',
        'application/vnd.oasis.opendocument.text']),
    ('Spreadsheets (.xlsx, .xls, .xlsm, .ods)', [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-excel', 'application/vnd.ms-excel.sheet.macroEnabled.12',
        'application/vnd.oasis.opendocument.spreadsheet']),
    ('Presentations (.pptx, .ppt, .pptm, .odp)', [
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/vnd.ms-powerpoint', 'application/vnd.ms-powerpoint.presentation.macroEnabled.12',
        'application/vnd.oasis.opendocument.presentation']),
    ('Text files', ['text/plain']),
    ('Images', ['image/png', 'image/jpeg', 'image/webp']),
    ('Music', ['audio/mpeg', 'audio/flac', 'audio/ogg', 'audio/mp4']),
    ('Videos', ['video/mp4', 'video/webm', 'video/x-matroska']),
]


def roots():
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    systems = [Path(p) for p in (os.environ.get('XDG_CONFIG_DIRS') or '/etc/xdg').split(':') if p]
    return config, state, systems


def desktop_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.+-]+\.desktop', value) or value.startswith('.'):
        raise ValueError('Choose an installed application')
    return value


def mime_type(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+', value):
        raise ValueError('Enter a file type such as application/pdf')
    return value


def validate(data):
    if not isinstance(data, dict) or set(data) != {'version', 'defaults', 'startup'} or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Unsupported application preferences')
    if not isinstance(data['defaults'], dict) or not isinstance(data['startup'], dict):
        raise ValueError('Invalid application preferences')
    for mime, app in data['defaults'].items():
        mime_type(mime); desktop_id(app)
    for name, choice in data['startup'].items():
        desktop_id(name)
        if not isinstance(choice, dict) or set(choice) - {'enabled', 'application'} or type(choice.get('enabled')) is not bool:
            raise ValueError('Invalid startup preference')
        if 'application' in choice:
            desktop_id(choice['application'])
            if name != 'hyprshell-' + choice['application']:
                raise ValueError('Invalid managed startup entry')
    return data


def saved():
    path = roots()[0] / 'hyprshell/applications.json'
    return validate(json.loads(path.read_text())) if path.exists() else {'version': 1, 'defaults': {}, 'startup': {}}


def parser(text=''):
    result = configparser.ConfigParser(interpolation=None, strict=False)
    result.optionxform = str
    result.read_string(text)
    return result


def rendered(document):
    stream = io.StringIO(); document.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def apps():
    from gi.repository import Gio
    result = {}
    for app in Gio.AppInfo.get_all():
        ident = app.get_id()
        if not ident or not app.should_show():
            continue
        try:
            desktop_id(ident)
        except ValueError:
            continue
        if not hasattr(app, 'get_filename'):
            continue
        source = Path(app.get_filename())
        if not source.is_file():
            continue
        result[ident] = {'id': ident, 'name': app.get_display_name(), 'types': list(app.get_supported_types() or []), 'path': str(source)}
    return result


def default_for(mime):
    from gi.repository import Gio
    app = Gio.AppInfo.get_default_for_type(mime, False)
    return app.get_id() if app else ''


def startup_files():
    config, _, systems = roots()
    result = {}
    for root in [config] + systems:
        for source in sorted((root / 'autostart').glob('*.desktop')):
            result.setdefault(source.name, source)
    return result


def startup_rows():
    result = []
    desktop = set((os.environ.get('XDG_CURRENT_DESKTOP') or 'Hyprland').split(':'))
    for name, source in startup_files().items():
        try:
            entry = parser(source.read_text())['Desktop Entry']
            if entry.get('Type', 'Application') != 'Application':
                continue
            enabled = entry.get('Hidden', 'false').lower() != 'true' and entry.get('X-GNOME-Autostart-enabled', 'true').lower() != 'false'
            reason = ''
            only = set(filter(None, entry.get('OnlyShowIn', '').split(';')))
            excluded = set(filter(None, entry.get('NotShowIn', '').split(';')))
            if (only and not only & desktop) or excluded & desktop:
                reason = 'Available in another desktop session'
            elif entry.get('TryExec') and not shutil.which(entry['TryExec']):
                reason = 'Required program is not installed'
            elif not entry.get('Exec'):
                reason = 'No launch command is available'
            elif entry.get('AutostartCondition') or entry.get('X-KDE-autostart-condition') or entry.get('X-GNOME-Autostart-Phase'):
                reason = 'Startup also depends on application-specific conditions'
            result.append({'id': name, 'name': entry.get('Name', name), 'enabled': enabled, 'reason': reason})
        except (OSError, UnicodeError, configparser.Error, KeyError):
            result.append({'id': name, 'name': name, 'enabled': False, 'reason': 'This startup entry could not be read'})
    return sorted(result, key=lambda row: row['name'].casefold())


def revision():
    config, _, systems = roots()
    paths = {config / 'hyprshell/applications.json', config / 'mimeapps.list'}
    desktops = [d.lower() for d in (os.environ.get('XDG_CURRENT_DESKTOP') or 'Hyprland').split(':')]
    for root in [config] + systems:
        paths.update(root / (d + '-mimeapps.list') for d in desktops)
        paths.add(root / 'mimeapps.list')
    paths.update(startup_files().values())
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path).encode()); digest.update(b'\0')
        digest.update(path.read_bytes() if path.exists() else b'<missing>')
    return digest.hexdigest()


def status(extra=None):
    installed = apps()
    groups = list(GROUPS)
    if extra:
        mime_type(extra); groups.append((extra, [extra]))
    associations = []
    for label, types in groups:
        current = [default_for(mime) for mime in types]
        candidates = [app['id'] for app in installed.values() if set(types) & set(app['types'])]
        # Preserve a current association even when its entry does not advertise the type.
        candidates = sorted(set(candidates + [app for app in current if app in installed]), key=lambda ident: installed[ident]['name'].casefold())
        associations.append({'label': label, 'types': types, 'current': current[0] if len(set(current)) == 1 else '',
                             'mixed': len(set(current)) > 1, 'candidates': candidates})
    return {'ok': True, 'revision': revision(), 'apps': [{k: v for k, v in app.items() if k != 'path'} for app in sorted(installed.values(), key=lambda app: app['name'].casefold())],
            'associations': associations, 'startup': startup_rows()}


def add_associations(text, choices):
    document = parser(text)
    for section in ('Default Applications', 'Added Associations'):
        if not document.has_section(section):
            document.add_section(section)
    for mime, ident in choices.items():
        document['Default Applications'][mime] = ident + ';'
        previous = document['Added Associations'].get(mime, '').split(';')
        document['Added Associations'][mime] = ';'.join([ident] + [a for a in previous if a and a != ident]) + ';'
        if document.has_section('Removed Associations'):
            removed = [a for a in document['Removed Associations'].get(mime, '').split(';') if a and a != ident]
            if removed:
                document['Removed Associations'][mime] = ';'.join(removed) + ';'
            else:
                document['Removed Associations'].pop(mime, None)
    return rendered(document)


def changes_for(data, installed, restoring=False):
    config, _, _ = roots()
    changes = {}
    skipped = []
    data = json.loads(json.dumps(data))
    for mime, ident in data['defaults'].items():
        if ident in ('chromium.desktop', 'chromium-browser.desktop') and ident not in installed:
            alternative = 'chromium.desktop' if ident == 'chromium-browser.desktop' else 'chromium-browser.desktop'
            if alternative in installed:
                data['defaults'][mime] = alternative
    defaults = {mime: ident for mime, ident in data['defaults'].items() if ident in installed}
    skipped.extend(ident for ident in data['defaults'].values() if ident not in installed)
    if defaults:
        path = config / 'mimeapps.list'
        changes[path] = add_associations(path.read_text() if path.exists() else '', defaults)
        # Desktop-specific defaults have higher priority than mimeapps.list.
        for desktop in (os.environ.get('XDG_CURRENT_DESKTOP') or 'Hyprland').split(':'):
            path = config / (desktop.lower() + '-mimeapps.list')
            if path.exists():
                document = parser(path.read_text())
                if document.has_section('Default Applications'):
                    for mime, ident in defaults.items():
                        if mime in document['Default Applications']:
                            document['Default Applications'][mime] = ident + ';'
                    changes[path] = rendered(document)
    existing = startup_files()
    for name, choice in data['startup'].items():
        if 'application' in choice:
            app = installed.get(choice['application'])
            if app is None:
                skipped.append(choice['application']); continue
            # UWSM reads the original desktop metadata, including Terminal=true
            # and working directory. The autostart generator itself does not.
            document = parser()
            document['Desktop Entry'] = {'Type': 'Application', 'Name': app['name'],
                                         'Exec': 'uwsm app -t service -- ' + choice['application'],
                                         'OnlyShowIn': 'Hyprland;'}
            entry = document['Desktop Entry']
        elif name in existing:
            document = parser(existing[name].read_text())
            entry = document['Desktop Entry']
            if choice['enabled'] and not entry.get('Exec'):
                # A user Hidden=true stub may mask a complete system entry.
                for root in roots()[2]:
                    source = root / 'autostart' / name
                    if source.is_file():
                        document = parser(source.read_text()); entry = document['Desktop Entry']; break
                if not entry.get('Exec'):
                    if restoring:
                        skipped.append(name); continue
                    raise ValueError('This startup entry has no launch command')
        else:
            skipped.append(name); continue
        entry['Hidden'] = 'false' if choice['enabled'] else 'true'
        entry['X-GNOME-Autostart-enabled'] = 'true' if choice['enabled'] else 'false'
        changes[config / 'autostart' / name] = rendered(document)
    return changes, sorted(set(skipped))


def transaction(changes):
    _, state, _ = roots()
    previous = {path: path.read_text() if path.exists() else None for path in changes}
    changed = {path: text for path, text in changes.items() if previous[path] != text}
    if not changed:
        return
    backup = state / 'hyprshell/backups' / ('applications-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(parents=True)
    manifest = []
    for index, path in enumerate(changed):
        manifest.append({'path': str(path), 'existed': previous[path] is not None, 'file': str(index)})
        if previous[path] is not None:
            (backup / str(index)).write_text(previous[path])
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    written = []
    try:
        for path, text in changed.items():
            atomic(path, text); written.append(path)
    except Exception as error:
        failures = []
        for path in reversed(written):
            try:
                if previous[path] is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic(path, previous[path])
            except Exception as rollback_error:
                failures.append(str(rollback_error))
        if failures:
            raise ValueError('Application update failed and could not be fully restored. Backups are available in Hyprshell state.') from error
        raise


def apply(request):
    if request.get('extra'):
        mime_type(request['extra'])
    config, state, _ = roots()
    with lock(state / 'hyprshell/applications.lock'):
        if request.get('expected') != revision():
            raise ValueError('Application preferences changed elsewhere. Refresh before saving.')
        data = saved(); installed = apps()
        operation = request.get('operation')
        if operation == 'default':
            ident = desktop_id(request['application'])
            if ident not in installed:
                raise ValueError('This application is no longer installed. Refresh and choose another.')
            types = request['types']
            if not isinstance(types, list) or not types or len(types) > 32:
                raise ValueError('Choose a file type')
            for mime in types:
                data['defaults'][mime_type(mime)] = ident
        elif operation in ('startup', 'add'):
            if type(request.get('enabled')) is not bool:
                raise ValueError('Choose whether this app starts at login')
            if operation == 'add':
                ident = desktop_id(request['application'])
                if ident not in installed:
                    raise ValueError('This application is no longer installed')
                app_entry = parser(Path(installed[ident]['path']).read_text())['Desktop Entry']
                for row in startup_rows():
                    if row['enabled'] and not row['reason']:
                        entry = parser(startup_files()[row['id']].read_text())['Desktop Entry']
                        if entry.get('Exec') == app_entry.get('Exec'):
                            raise ValueError('This app already starts at login. Use its existing startup toggle.')
                name = 'hyprshell-' + ident
                if name not in data['startup'] and name in startup_files():
                    raise ValueError('A startup entry already uses this name. Refresh and toggle that entry.')
                data['startup'][name] = {'enabled': request['enabled'], 'application': ident}
            else:
                name = desktop_id(request['entry'])
                if name not in startup_files():
                    raise ValueError('This startup entry changed. Refresh before saving.')
                choice = data['startup'].get(name, {}).copy()
                choice['enabled'] = request['enabled']; data['startup'][name] = choice
        else:
            raise ValueError('Unknown application action')
        validate(data)
        # A single edit must not reapply unrelated saved preferences over manual changes.
        delta = {'version': 1, 'defaults': {}, 'startup': {}}
        if operation == 'default':
            delta['defaults'] = {mime: ident for mime in types}
        else:
            delta['startup'] = {name: data['startup'][name]}
        changes, _ = changes_for(delta, installed)
        changes[config / 'hyprshell/applications.json'] = json.dumps(data, indent=2) + '\n'
        transaction(changes)
    result = status(request.get('extra'))
    result['message'] = 'Default application saved.' if operation == 'default' else 'Startup preference saved. It takes effect at your next login.'
    return result


def restore():
    config, state, _ = roots()
    if not (config / 'hyprshell/applications.json').exists():
        return {'ok': True, 'skipped': []}
    with lock(state / 'hyprshell/applications.lock'):
        changes, skipped = changes_for(saved(), apps(), restoring=True)
        transaction(changes)
    return {'ok': True, 'skipped': skipped}


def main():
    arguments = argparse.ArgumentParser()
    arguments.add_argument('--request-json')
    arguments.add_argument('--restore', action='store_true')
    args = arguments.parse_args()
    try:
        request = json.loads(args.request_json or '{}')
        result = restore() if args.restore else status(request.get('extra')) if request.get('operation') == 'status' else apply(request)
    except Exception as error:
        print(json.dumps({'ok': False, 'message': str(error)})); return 1
    print(json.dumps(result)); return 0


if __name__ == '__main__':
    sys.exit(main())
