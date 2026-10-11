#!/usr/bin/env python3
"""Validated, backed-up settings transactions. No shell evaluation of user input."""
import argparse
import copy
from contextlib import contextmanager
from datetime import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shlex
import signal
import shutil
import subprocess
import sys
import tempfile

DEFAULTS = json.loads(Path(__file__).with_name('defaults.json').read_text())
HYPR = {
    'gapsIn': ('general.gaps_in', 0, 100),
    'gapsOut': ('general.gaps_out', 0, 100),
    'borderSize': ('general.border_size', 0, 20),
    'rounding': ('decoration.rounding', 0, 100),
    'activeOpacity': ('decoration.active_opacity', 0, 1),
    'inactiveOpacity': ('decoration.inactive_opacity', 0, 1),
    'blur': ('decoration.blur.enabled', None, None),
    'blurSize': ('decoration.blur.size', 1, 20),
    'blurPasses': ('decoration.blur.passes', 1, 4),
    'blurVibrancy': ('decoration.blur.vibrancy', 0, 1),
    'shadows': ('decoration.shadow.enabled', None, None),
    'animations': ('animations.enabled', None, None),
    'pointerSpeed': ('input.sensitivity', -1, 1),
    'mouseNaturalScroll': ('input.natural_scroll', None, None),
    'touchpadNaturalScroll': ('input.touchpad.natural_scroll', None, None),
    'tapToClick': ('input.touchpad.tap_to_click', None, None),
    'disableWhileTyping': ('input.touchpad.disable_while_typing', None, None),
    'repeatRate': ('input.repeat_rate', 1, 100),
    'repeatDelay': ('input.repeat_delay', 100, 2000),
    'keyboardLayouts': ('input.kb_layout', 'layouts', None),
    'layoutSwitch': ('input.kb_options', 'switch', None),
}
MARKER = '-- Hyprshell settings override'


def number(value, low, high, integer=False):
    if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f'Expected a number from {low} to {high}, got {value!r}')
    if integer and int(value) != value:
        raise ValueError('Expected a whole number')


def validate(data):
    if not isinstance(data, dict) or type(data.get('version')) is not int or data['version'] != 1:
        raise ValueError('Unsupported settings version')
    data = copy.deepcopy(data)
    # Ignore only the retired experiment, preserving validation of other keys.
    sections = [data.get('bar')] + (data.get('items', []) if isinstance(data.get('items', []), list) else [])
    for section in sections:
        if isinstance(section, dict):
            for key in ('genieEffect', 'genieOpenDuration', 'genieCloseDuration'):
                section.pop(key, None)
    if set(data) - set(DEFAULTS):
        raise ValueError('Unknown settings section')
    result = json.loads(json.dumps(DEFAULTS))
    bar = data.get('bar', {})
    if not isinstance(bar, dict) or set(bar) - set(result['bar']):
        raise ValueError('Unknown bar setting')
    result['bar'].update(bar)
    bar = result['bar']
    if bar['position'] not in ('top', 'left', 'right', 'bottom'):
        raise ValueError('Bar position must be top, left, right, or bottom')
    if type(bar['visible']) is not bool:
        raise ValueError('Bar visibility must be boolean')
    if bar['workspaceScope'] not in ('all', 'selected'):
        raise ValueError('Workspace scope must be "all" or "selected"')
    workspace_list = bar['workspaceList']
    if not isinstance(workspace_list, list) or any(type(w) is not int or not 1 <= w <= 99 for w in workspace_list):
        raise ValueError('Workspace list must be whole numbers from 1 to 99')
    if len(set(workspace_list)) != len(workspace_list):
        raise ValueError('Workspace list must not contain duplicates')
    if bar['workspaceScope'] == 'selected' and not workspace_list:
        raise ValueError('Choose at least one workspace for the selected scope')
    overrides = bar['workspaceOverrides']
    if not isinstance(overrides, dict) or any(
        not isinstance(key, str) or not re.fullmatch(r'[1-9][0-9]?', key) or type(value) is not bool
        for key, value in overrides.items()
    ):
        raise ValueError('Workspace overrides must map workspace numbers 1–99 to booleans')
    number(bar['popdownTranslucency'], 0, 1)
    if type(bar['adaptiveColors']) is not bool:
        raise ValueError('adaptiveColors must be boolean')
    if type(bar['randomVibrantColors']) is not bool:
        raise ValueError('randomVibrantColors must be boolean')
    if bar['iconSize'] != 0 or type(bar['iconSize']) is bool:
        number(bar['iconSize'], 8, 48, True)
    if bar['background'] not in ('inherit', 'on', 'off'):
        raise ValueError('Invalid global background')
    if bar['sharedBackground'] not in ('inherit', 'on', 'off'):
        raise ValueError('Invalid shared background')
    for key, low, high in [('height', 28, 80), ('marginTop', 0, 100), ('marginSide', 0, 200), ('spacing', 0, 30), ('groupSpacing', 0, 30)]:
        number(bar[key], low, high, True)
    if not isinstance(bar['clockFormat'], str) or not 1 <= len(bar['clockFormat']) <= 100:
        raise ValueError('Clock format must contain 1–100 characters')
    items = data.get('items', [])
    if not isinstance(items, list):
        raise ValueError('items must be a list')
    known = {i['id']: i for i in result['items']}
    seen = set()
    for item in items:
        if not isinstance(item, dict) or item.get('id') not in known or item['id'] in seen:
            raise ValueError('Unknown or duplicate bar item')
        seen.add(item['id'])
        target = known[item['id']]
        if set(item) - set(target):
            raise ValueError('Unknown item setting')
        target.update(item)
        for key in ('enabled', 'hideText', 'hideIcon'):
            if type(target[key]) is not bool:
                raise ValueError(f'{key} must be boolean')
        for key, choices in [('side', ('left', 'center', 'right')), ('adaptiveColors', ('inherit', 'on', 'off')), ('background', ('inherit', 'on', 'off')), ('sharedBackground', ('inherit', 'on', 'off'))]:
            if target[key] not in choices:
                raise ValueError(f'Invalid {key}')
        if not isinstance(target['pillGroup'], str) or len(target['pillGroup']) > 40 or any(ord(c) < 32 for c in target['pillGroup']):
            raise ValueError('Pill group must be a name of at most 40 characters')
        for key in ('text', 'icon'):
            if not isinstance(target[key], str) or len(target[key]) > 200:
                raise ValueError('Text/icon must be at most 200 characters')
        for key in ('textColor', 'iconColor', 'backgroundColor', 'outlineColor'):
            if not isinstance(target[key], str) or (target[key] and not re.fullmatch(r'#[0-9a-fA-F]{6}', target[key])):
                raise ValueError(f'{key} must be empty or #RRGGBB')
        for key, low, high, integer in [('order', 0, 1000, True), ('opacity', 0, 1, False), ('fontSize', 0, 48, True), ('radius', -1, 50, True), ('spacingLeft', -200, 200, True), ('spacingRight', -200, 200, True), ('paddingLeft', -200, 200, True), ('paddingRight', -200, 200, True)]:
            number(target[key], low, high, integer)
        if target['iconSize'] != 0 or type(target['iconSize']) is bool:
            number(target['iconSize'], 8, 48, True)
        if target['popdownTranslucency'] != -1:
            number(target['popdownTranslucency'], 0, 1)
        alpha = target['backgroundOpacity']
        if alpha != -1:
            number(alpha, 0, 1)
    hypr = data.get('hyprland', {})
    if not isinstance(hypr, dict) or set(hypr) - set(HYPR):
        raise ValueError('Unknown Hyprland setting')
    for key, value in hypr.items():
        _, low, high = HYPR[key]
        if low == 'layouts':
            if not isinstance(value, str) or len(value) > 100 or not re.fullmatch(r'[a-z0-9_]+(?:,[a-z0-9_]+){0,3}', value):
                raise ValueError('Choose one to four comma-separated keyboard layout codes')
            for code in value.split(','):
                if not (Path('/usr/share/X11/xkb/symbols') / code).is_file():
                    raise ValueError(f'Keyboard layout is not installed: {code}')
        elif low == 'switch':
            if value not in ('grp:alt_shift_toggle', 'grp:win_space_toggle', 'grp:caps_toggle'):
                raise ValueError('Unknown keyboard layout switching shortcut')
        elif low is None:
            if type(value) is not bool:
                raise ValueError(f'{key} must be boolean')
        else:
            number(value, low, high, high != 1)
    locking = data.get('locking', {})
    if not isinstance(locking, dict) or set(locking) - set(result['locking']):
        raise ValueError('Unknown screen locking setting')
    result['locking'].update(locking)
    locking = result['locking']
    for key in ('enabled', 'beforeSleep'):
        if type(locking[key]) is not bool:
            raise ValueError(f'{key} must be boolean')
    number(locking['idleMinutes'], 0, 240, True)
    lock_argv(locking['command'])
    notifications = data.get('notifications', {})
    if not isinstance(notifications, dict) or set(notifications) - set(result['notifications']):
        raise ValueError('Unknown notification setting')
    result['notifications'].update(notifications)
    notifications = result['notifications']
    for key in ('popups', 'doNotDisturb', 'criticalBypass'):
        if type(notifications[key]) is not bool:
            raise ValueError(f'{key} must be boolean')
    number(notifications['popupSeconds'], 2, 30, True)
    apps = notifications['apps']
    if not isinstance(apps, dict) or len(apps) > 200:
        raise ValueError('Expected at most 200 notification app preferences')
    for app, mode in apps.items():
        if not isinstance(app, str) or not app.strip() or len(app) > 200 or any(c in app for c in '\n\r\0'):
            raise ValueError('Invalid notification application name')
        if mode not in ('inbox', 'off'):
            raise ValueError('Unknown application notification preference')
    power = data.get('power', {})
    if not isinstance(power, dict) or set(power) - set(result['power']):
        raise ValueError('Unknown power setting')
    result['power'].update(power)
    power = result['power']
    for key in ('dimMinutes', 'offMinutes', 'suspendMinutes'):
        number(power[key], 0, 240, True)
    number(power['dimPercent'], 1, 100, True)
    if power['lidAction'] not in ('system', 'suspend', 'ignore'):
        raise ValueError('Unknown lid behavior')
    if power['profile'] not in ('system', 'power-saver', 'balanced', 'performance'):
        raise ValueError('Unknown power profile')
    if type(power['separateBatteryTimers']) is not bool:
        raise ValueError('Separate battery timers must be boolean')
    for key in ('batteryDimMinutes', 'batteryOffMinutes', 'batterySuspendMinutes'):
        number(power[key], 0, 240, True)
    number(power['batteryDimPercent'], 1, 100, True)
    battery_timers = [power[key] for key in ('batteryDimMinutes', 'batteryOffMinutes', 'batterySuspendMinutes') if power[key]]
    if battery_timers != sorted(battery_timers) or len(battery_timers) != len(set(battery_timers)):
        raise ValueError('Battery timers must increase: dim, screen off, then suspend')
    timers = [power[key] for key in ('dimMinutes', 'offMinutes', 'suspendMinutes') if power[key]]
    if timers != sorted(timers) or len(timers) != len(set(timers)):
        raise ValueError('Enabled timers must be in order: dim, screen off, then suspend, with different times')
    clipboard = data.get('clipboard', {})
    if not isinstance(clipboard, dict) or set(clipboard) - set(result['clipboard']):
        raise ValueError('Unknown clipboard setting')
    result['clipboard'].update(clipboard)
    number(result['clipboard']['maxItems'], 10, 200, True)
    for key in ('enabled', 'includeImages'):
        if type(result['clipboard'][key]) is not bool:
            raise ValueError('Clipboard toggles must be boolean')
    accessibility = data.get('accessibility', {})
    if not isinstance(accessibility, dict) or set(accessibility) - set(result['accessibility']):
        raise ValueError('Unknown accessibility setting')
    result['accessibility'].update(accessibility)
    number(result['accessibility']['textScale'], 1, 1.5)
    for key in ('highContrast', 'reducedMotion'):
        if type(result['accessibility'][key]) is not bool:
            raise ValueError(f'{key} must be boolean')
    result['hyprland'] = hypr
    return result


def lock_argv(command):
    if not isinstance(command, str) or not command.strip() or len(command) > 2000 or any(c in command for c in '\n\r\0'):
        raise ValueError('Lock command must contain 1–2000 characters on one line')
    args = shlex.split(command)
    if not args or not args[0]:
        raise ValueError('Enter a locker executable and optional arguments')
    return [os.path.expanduser(arg) for arg in args]


def lock_dependencies(settings):
    if not shutil.which('hypridle'):
        raise ValueError('Install hypridle to enable automatic locking')
    if not shutil.which(lock_argv(settings['command'])[0]):
        raise ValueError('Lock program was not found. Install it or enter its full path')


def effective_power(power, on_battery=False):
    result = dict(power)
    if on_battery and power.get('separateBatteryTimers'):
        for key in ('dimMinutes', 'offMinutes', 'suspendMinutes', 'dimPercent'):
            result[key] = power['battery' + key[0].upper() + key[1:]]
    return result


def power_idle_enabled(power):
    return any(power.get(key, 0) for key in ('dimMinutes', 'offMinutes', 'suspendMinutes'))


def idle_dependencies(locking, power):
    if locking['enabled']:
        lock_dependencies(locking)
    elif power_idle_enabled(power) and not shutil.which('hypridle'):
        raise ValueError('Install hypridle to enable power timers')
    if power['dimMinutes'] and not shutil.which('brightnessctl'):
        raise ValueError('Install brightnessctl to dim the screen')
    if power['lidAction'] != 'system' and not shutil.which('systemd-inhibit'):
        raise ValueError('Install systemd to manage lid behavior')


def render_idle(settings, power=None):
    # Hyprlang interprets these characters before its command reaches a shell.
    path = str(Path(__file__).resolve())
    helper = str(Path(__file__).resolve().with_name('power.py'))
    if any(c in path + sys.executable for c in '\n\r#$'):
        raise ValueError('Unsupported characters in idle helper path')
    command = shlex.join([sys.executable, path, '--lock'])
    power_command = shlex.join([sys.executable, helper])
    locking = power is None or settings['enabled']
    power = power or DEFAULTS['power']
    text = '# Generated by Hyprshell; edit locking and power in Settings.\ngeneral {\n'
    if locking:
        text += '    lock_cmd = ' + command + '\n'
        if settings['beforeSleep']:
            text += '    before_sleep_cmd = loginctl lock-session\n'
    if power_idle_enabled(power):
        text += '    after_sleep_cmd = ' + power_command + ' --resume\n'
    text += '}\n'
    if locking and settings['idleMinutes']:
        text += '\nlistener {\n    timeout = ' + str(int(settings['idleMinutes'] * 60)) + '\n    on-timeout = loginctl lock-session\n}\n'
    for key, action, resume in (('dimMinutes', '--dim', '--restore'),
                                 ('offMinutes', '--screen-off', '--resume'),
                                 ('suspendMinutes', None, None)):
        if not power[key]:
            continue
        text += '\nlistener {\n    timeout = ' + str(int(power[key] * 60)) + '\n'
        text += '    on-timeout = ' + (power_command + ' ' + action if action else 'systemctl suspend') + '\n'
        if resume:
            text += '    on-resume = ' + power_command + ' ' + resume + '\n'
        text += '}\n'
    return text


def read_preferences():
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    path = config / 'hyprshell/settings.json'
    return validate(json.loads(path.read_text()) if path.exists() else DEFAULTS)


def read_locking():
    return read_preferences()['locking']


def read_power():
    return read_preferences()['power']


def run_locker():
    settings = read_locking()
    args = lock_argv(settings['command'])
    if not shutil.which(args[0]):
        raise ValueError('Lock program was not found: ' + args[0])
    # Hold a separate lock throughout the foreground locker lifetime, so idle,
    # sleep and manual requests cannot start multiple lock screens.
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    path = state / 'hyprshell/locker.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        # The bundled lock theme resolves its relative images from this folder.
        # Keep custom locker commands (and their relative arguments) untouched.
        options = {}
        if args == ['hyprlock']:
            options['cwd'] = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'hypr'
        return subprocess.run(args, check=False, **options).returncode


def run_idle(on_battery=False):
    settings = read_locking()
    power = effective_power(read_power(), on_battery)
    if not settings['enabled'] and not power_idle_enabled(power):
        return 0
    idle_dependencies(settings, power)
    existing = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'hypridle'], capture_output=True)
    if existing.returncode == 0:
        raise ValueError('Another hypridle is running. Disable its service or autostart before using Hyprshell idle settings')
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    path = config / 'hyprshell/hypridle.conf'
    atomic(path, render_idle(settings, power))
    child_env = dict(os.environ, HYPRSHELL_IDLE_BATTERY='1' if on_battery else '0')
    child = subprocess.Popen(['hypridle', '-c', str(path)], env=child_env)
    def stop(signum, frame):
        raise SystemExit(0)
    old_handlers = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        return child.wait()
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if power_idle_enabled(power):
            # Restore dimmed/off screens when settings change or the shell exits.
            subprocess.run([sys.executable, str(Path(__file__).with_name('power.py')), '--resume'], timeout=25)


def render_hypr(settings, lua, accessibility=None):
    settings = dict(settings)
    if (accessibility or {}).get('reducedMotion'):
        settings['animations'] = False
    if not lua:
        return '# Generated by Hyprshell\n' + ''.join(f'{HYPR[k][0].replace(".", ":")} = {str(v).lower()}\n' for k, v in settings.items())
    tree = {}
    for key, value in settings.items():
        parts = HYPR[key][0].split('.')
        node = tree
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    def encode(node):
        if isinstance(node, dict):
            return '{' + ', '.join(k + ' = ' + encode(v) for k, v in node.items()) + '}'
        if isinstance(node, str):
            return json.dumps(node)
        return str(node).lower()
    return '-- Generated by Hyprshell\nhl.config(' + encode(tree) + ')\n'


def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.hyprshell-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def bar_visible(bar, workspace):
    overrides = bar.get('workspaceOverrides', {})
    if str(workspace) in overrides:
        return overrides[str(workspace)]
    return bar['visible'] and (bar['workspaceScope'] == 'all' or workspace in bar['workspaceList'])


def save(data, expected=None, *, toggle_workspace=None):
    data = validate(data)
    if toggle_workspace is not None:
        if type(toggle_workspace) is not int or not 1 <= toggle_workspace <= 99:
            raise ValueError('Choose a workspace number from 1 to 99')
    home = Path.home()
    config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state')
    target = config / 'hyprshell/settings.json'
    with lock(state / 'hyprshell/settings.lock'):
        current = validate(json.loads(target.read_text())) if target.exists() else validate(DEFAULTS)
        if toggle_workspace is not None:
            data = copy.deepcopy(current)
            data['bar']['workspaceOverrides'][str(toggle_workspace)] = not bar_visible(current['bar'], toggle_workspace)
        if expected is not None and current != validate(expected):
            raise ValueError('Settings changed outside this window. Close and reopen settings before applying.')
        if data['locking']['command'] != current['locking']['command'] and not shutil.which(lock_argv(data['locking']['command'])[0]):
            raise ValueError('Lock program was not found. Install it or enter its full path')
        if data['locking'] != current['locking'] or data['power'] != current['power']:
            idle_dependencies(data['locking'], data['power'])
            idle_dependencies(data['locking'], effective_power(data['power'], True))
            render_idle(data['locking'], data['power'])
        changes = {}
        hypr_changed = data['hyprland'] != current['hyprland'] or data['accessibility']['reducedMotion'] != current['accessibility']['reducedMotion']
        if hypr_changed:
            main = config / 'hypr/hyprland.lua'
            lua = main.exists()
            if not lua:
                main = config / 'hypr/hyprland.conf'
            if not main.is_file():
                raise ValueError('No Hyprland config found. Bar settings can still be used without Hyprland overrides.')
            override = config / ('hyprshell/overrides.lua' if lua else 'hyprshell/overrides.conf')
            changes[override] = render_hypr(data['hyprland'], lua, data['accessibility'])
            original = main.read_text()
            marker = MARKER if lua else '# Hyprshell settings override'
            if marker not in original:
                if lua:
                    source = 'dofile(' + json.dumps(str(override), ensure_ascii=False) + ')'
                else:
                    if any(c in str(override) for c in '\n\r#'):
                        raise ValueError('Unsupported characters in Hyprland source path')
                    source = 'source = ' + str(override)
                changes[main] = original.rstrip() + '\n\n' + marker + '\n' + source + '\n'
        changes[target] = json.dumps(data, indent=2) + '\n'
        changes = {p: text for p, text in changes.items() if not p.exists() or p.read_text() != text}
        if not changes:
            return {'ok': True, 'message': 'No changes to apply.'}
        backup = state / 'hyprshell/backups' / ('settings-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        backup.mkdir(parents=True)
        previous = {p: p.read_text() if p.exists() else None for p in changes}
        manifest = []
        for index, (path, text) in enumerate(previous.items()):
            entry = {'path': str(path), 'existed': text is not None, 'file': str(index)}
            manifest.append(entry)
            if text is not None:
                (backup / str(index)).write_text(text)
        (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        applied = []
        reload_live = hypr_changed and bool(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'))
        try:
            for path, text in changes.items():
                atomic(path, text)
                applied.append(path)
            if reload_live:
                subprocess.run(['hyprctl', 'reload'], check=True, capture_output=True, text=True, timeout=15)
                errors = subprocess.run(['hyprctl', 'configerrors'], check=True, capture_output=True, text=True, timeout=10)
                if errors.stdout.strip() and errors.stdout.strip().lower() != 'ok':
                    raise ValueError(errors.stdout.strip())
        except Exception:
            for path in reversed(applied):
                if previous[path] is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic(path, previous[path])
            if reload_live:
                subprocess.run(['hyprctl', 'reload'], capture_output=True, timeout=15)
            raise
        return {'ok': True, 'message': 'Settings applied.' + (' Hyprland changes will load next session.' if hypr_changed and not reload_live else ''), 'backup': str(backup)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--save-json')
    parser.add_argument('--toggle-bar', type=int, metavar='WORKSPACE')
    parser.add_argument('--lock', action='store_true')
    parser.add_argument('--idle', action='store_true')
    parser.add_argument('--battery', action='store_true')
    parser.add_argument('--expected-json')
    args = parser.parse_args()
    try:
        if args.lock:
            return run_locker()
        if args.idle:
            return run_idle(args.battery)
        if args.toggle_bar is not None:
            result = save(DEFAULTS, toggle_workspace=args.toggle_bar)
            print(json.dumps(result))
            return 0
        if not args.save_json:
            parser.error('Provide --save-json, --lock or --idle')
        result = save(json.loads(args.save_json), json.loads(args.expected_json) if args.expected_json else None)
    except Exception as error:
        if args.lock or args.idle:
            print(str(error), file=sys.stderr)
            return 1
        print(json.dumps({'ok': False, 'message': str(error)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
