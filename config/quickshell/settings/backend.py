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
import time

DEFAULTS = json.loads(Path(__file__).with_name('defaults.json').read_text())
HYPR = {
    'gapsIn': ('general.gaps_in', 0, 100),
    'gapsOut': ('general.gaps_out', 0, 100),
    'gapsOutTop': ('general.gaps_out', 0, 100),
    'gapsOutRight': ('general.gaps_out', 0, 100),
    'gapsOutBottom': ('general.gaps_out', 0, 100),
    'gapsOutLeft': ('general.gaps_out', 0, 100),

    'borderSize': ('general.border_size', 0, 20),
    'rounding': ('decoration.rounding', 0, 100),
    'activeOpacity': ('decoration.active_opacity', 0, 1),
    'inactiveOpacity': ('decoration.inactive_opacity', 0, 1),
    'fullscreenOpacity': ('decoration.fullscreen_opacity', 0, 1),
    'effectWorkspaceScope': (None, 'scope', None),
    'effectWorkspaces': (None, 'workspaces', None),
    'blurFocus': (None, 'focus', None),
    'blur': ('decoration.blur.enabled', None, None),
    'blurSize': ('decoration.blur.size', 1, 20),
    'blurPasses': ('decoration.blur.passes', 1, 4),
    'blurVibrancy': ('decoration.blur.vibrancy', 0, 1),
    'blurNoise': ('decoration.blur.noise', 0, 1),
    'blurContrast': ('decoration.blur.contrast', 0, 2),
    'blurBrightness': ('decoration.blur.brightness', 0, 2),
    'blurVibrancyDarkness': ('decoration.blur.vibrancy_darkness', 0, 1),
    'blurIgnoreOpacity': ('decoration.blur.ignore_opacity', None, None),
    'blurOptimizations': ('decoration.blur.new_optimizations', None, None),
    'blurXray': ('decoration.blur.xray', None, None),
    'blurSpecial': ('decoration.blur.special', None, None),
    'blurPopups': ('decoration.blur.popups', None, None),
    'blurPopupsIgnoreAlpha': ('decoration.blur.popups_ignorealpha', 0, 1),
    'blurInputMethods': ('decoration.blur.input_methods', None, None),
    'blurInputMethodsIgnoreAlpha': ('decoration.blur.input_methods_ignorealpha', 0, 1),
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
    if bar['verticalPresentation'] not in ('edge', 'compact'):
        raise ValueError('Vertical presentation must be edge or compact')
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
    for key, low, high in [('height', 28, 80), ('marginTop', 0, 100), ('paddingBottom', 0, 100), ('marginSide', 0, 200), ('spacing', 0, 30), ('groupSpacing', 0, 30)]:
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
        if low == 'scope':
            if value not in ('all', 'selected'):
                raise ValueError('Choose all or selected workspaces')
        elif low == 'focus':
            if value not in ('both', 'focused', 'unfocused'):
                raise ValueError('Choose which windows receive blur')
        elif low == 'workspaces':
            if not isinstance(value, list) or len(value) > 99 or any(type(v) is not int or not 1 <= v <= 99 for v in value) or len(set(value)) != len(value):
                raise ValueError('Choose unique workspace numbers from 1 to 99')
        elif low == 'layouts':
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
            number(value, low, high, key not in ('blurContrast', 'blurBrightness') and high != 1)
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
    validate_panels(data, result)
    return result


def validate_panels(data, result):
    """Validate reserved layouts too; never silently move or disable a component."""
    panels = data.get('panels', {})
    if not isinstance(panels, dict) or set(panels) - set(result['panels']):
        raise ValueError('Unknown panel component')
    for name, target in result['panels'].items():
        saved = panels.get(name, {})
        if not isinstance(saved, dict) or set(saved) - set(target):
            raise ValueError(f'Unknown {name} setting')
        target.update(saved)
        if type(target['enabled']) is not bool:
            raise ValueError(f'{name} enabled must be boolean')
        monitors = target['monitors']
        if not isinstance(monitors, list) or any(
            not isinstance(m, str) or not m or len(m) > 128 or any(ord(c) < 32 for c in m)
            for m in monitors
        ) or len(set(monitors)) != len(monitors):
            raise ValueError(f'{name} monitors must be unique connector names; empty means all')
        modes = ('always',) if name == 'hyprpane' else ('always', 'auto-hide', 'dodge')
        if target['hideMode'] not in modes:
            raise ValueError(f'Invalid {name} hide mode')
        if name == 'hyprpane':
            continue  # Its established appearance/edge/visibility live in bar + items.
        if target['position'] not in ('top', 'bottom', 'left', 'right'):
            raise ValueError(f'{name} position must be top, bottom, left, or right')
        if type(target['visible']) is not bool:
            raise ValueError(f'{name} visibility must be boolean')
        if target['workspaceScope'] not in ('all', 'selected'):
            raise ValueError(f'Invalid {name} workspace scope')
        workspaces = target['workspaceList']
        if not isinstance(workspaces, list) or any(type(w) is not int or not 1 <= w <= 99 for w in workspaces) or len(set(workspaces)) != len(workspaces):
            raise ValueError(f'{name} workspace list must contain unique numbers 1–99')
        if target['workspaceScope'] == 'selected' and not workspaces:
            raise ValueError(f'Choose at least one {name} workspace')
        overrides = target['workspaceOverrides']
        if not isinstance(overrides, dict) or any(
            not isinstance(w, str) or not re.fullmatch(r'[1-9][0-9]?', w) or type(v) is not bool
            for w, v in overrides.items()
        ):
            raise ValueError(f'{name} workspace overrides must map numbers 1–99 to booleans')
        for key, low, high in [('thickness', 28, 160), ('marginEdge', 0, 100), ('marginEnds', 0, 200), ('windowGap', 0, 100), ('iconSize', 8, 96), ('spacing', 0, 30)]:
            number(target[key], low, high, True)
        if target['background'] not in ('inherit', 'on', 'off'):
            raise ValueError(f'Invalid {name} background')
        if name == 'hyprdock':
            number(target['backgroundOpacity'], 0, 1)
    pins = data.get('pins', {})
    if not isinstance(pins, dict) or set(pins) - set(result['pins']):
        raise ValueError('Unknown pin setting')
    result['pins'].update(pins)
    if result['pins']['mode'] not in ('shared', 'separate'):
        raise ValueError('Pin mode must be shared or separate')
    for name in ('shared', 'hyprdock', 'hyprbar'):
        ids = result['pins'][name]
        if not isinstance(ids, list) or any(
            not desktop_id(app)
            for app in ids
        ) or len(set(ids)) != len(ids):
            raise ValueError('Pins must be unique desktop application IDs ending in .desktop')
    matches = result['pins']['matches']
    if not isinstance(matches, dict) or len(matches) > 512 or any(
        not isinstance(key, str) or not key.strip() or len(key) > 255
        or any(ord(c) < 32 for c in key) or not desktop_id(app)
        for key, app in matches.items()
    ):
        raise ValueError('App matches must map window classes/app IDs to desktop application IDs')
    validate_panel_layout(result)


def desktop_id(value):
    # A desktop filename, never a path or an executable command. Launchers pass
    # these as argv; unusual filenames use DesktopEntry.execute instead of UWSM.
    return (isinstance(value, str) and 8 < len(value) <= 255
            and value.endswith('.desktop') and value == value.strip()
            and not any(c in '/\\' or ord(c) < 32 or ord(c) == 127 for c in value))


def application_action(current, action):
    """Apply a narrow edit to the latest locked preferences, preserving UI drafts."""
    if not isinstance(action, dict):
        raise ValueError('Invalid application action')
    data = copy.deepcopy(current)
    pins = data['pins']
    kind = action.get('action')
    if kind == 'mode':
        pins['mode'] = action.get('mode')
    elif kind == 'match':
        key, app = action.get('key'), action.get('id')
        if not isinstance(key, str) or not key.strip():
            raise ValueError('Choose a window class/app ID')
        if app is None:
            pins['matches'].pop(key, None)
        else:
            pins['matches'][key] = app
    elif kind in ('pin', 'unpin', 'reorder'):
        component, app = action.get('component'), action.get('id')
        if component not in ('hyprdock', 'hyprbar') or not desktop_id(app):
            raise ValueError('Choose an app component and desktop application ID')
        target = 'shared' if pins['mode'] == 'shared' else component
        ids = pins[target]
        if kind == 'pin' and app not in ids:
            ids.append(app)
        elif kind == 'unpin' and app in ids:
            ids.remove(app)
        elif kind == 'reorder':
            index = action.get('index')
            if app not in ids or type(index) is not int or not 0 <= index < len(ids):
                raise ValueError('Choose an existing pin and a valid position')
            ids.remove(app)
            ids.insert(index, app)
    else:
        raise ValueError('Unknown application action')
    return validate(data)


def panel_config(data, name):
    """One compatibility view; there is no second copy of Hyprpane preferences."""
    panel = data['panels'][name]
    return {**data['bar'], **panel} if name == 'hyprpane' else panel


def validate_panel_layout(data):
    panels = {name: panel_config(data, name) for name in data['panels']}
    # The unnamed bucket catches future/hotplug outputs selected by an empty list.
    monitors = {None} | {m for panel in panels.values() for m in panel['monitors']}
    for monitor in sorted(monitors, key=lambda m: m or ''):
        for workspace in range(0, 100):  # 0 also covers unnumbered/special workspaces.
            active = [(name, panel) for name, panel in panels.items()
                      if panel['enabled'] and (not panel['monitors'] or monitor in panel['monitors'])
                      and bar_visible(panel, workspace)]
            location = f"{monitor or 'other monitors'}, workspace {workspace or 'unnumbered'}"
            if len(active) > 2:
                raise ValueError(f'Panel conflict on {location}: at most two components may be visible. Disable a component or change its monitor/workspace visibility.')
            if len(active) == 2 and active[0][1]['position'] == active[1][1]['position']:
                raise ValueError(f"Panel conflict on {location}: {active[0][0]} and {active[1][0]} both use {active[0][1]['position']}. Choose another edge or disable a component.")


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
            # Auto detection sees our Python wrapper rather than hyprlock.
            # Wait for the compositor's lock notification before suspending.
            text += '    inhibit_sleep = 3\n'
    if power_idle_enabled(power) or locking:
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
        if Path(args[0]).name != 'hyprlock':
            return supervise_locker(args, options)
        # Keep Hyprlock diagnostics across sleep and shell restarts.
        log_path = path.with_name('locker.log')
        if log_path.exists() and log_path.stat().st_size > 1024 * 1024:
            log_path.replace(log_path.with_suffix('.log.previous'))
        with log_path.open('a', buffering=1) as log:
            os.chmod(log_path, 0o600)
            options.update(stdout=log, stderr=subprocess.STDOUT)
            return supervise_locker(args, options)


def session_locked():
    """Return the compositor's actual lock state, or None if unavailable."""
    if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        return None
    try:
        result = subprocess.run(['hyprctl', '-j', 'locked'], capture_output=True,
                                text=True, timeout=3)
        if result.returncode == 0:
            locked = json.loads(result.stdout).get('locked')
            if type(locked) is bool:
                return locked
    except (OSError, subprocess.TimeoutExpired, ValueError, AttributeError):
        pass
    return None


def recover_locker():
    # Resume may outlive the original wrapper or its retry budget. The same
    # flock in run_locker makes this harmless when supervision is still alive.
    if session_locked() is True:
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--lock'],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


# A locker killed by a signal (for example
# hyprlock aborting after a suspend/resume or display power cycle) has instead
# died while the session must stay locked. Relaunch it so the compositor can
# hand the lock to the new client instead of showing a dead, clientless screen.
LOCKER_RESTART_DELAY = 1.0
LOCKER_HEALTHY_SECONDS = 30.0
LOCKER_MAX_RESTARTS = 10
LOCKER_RECOVERY_DELAY = 10.0


def supervise_locker(args, options):
    restarts = 0
    hyprlock = Path(args[0]).name == 'hyprlock'
    while True:
        started = time.monotonic()
        code = subprocess.run(args, check=False, **options).returncode
        # Exit codes alone cannot establish whether the session unlocked.
        # Keep recovery alive while Hyprland confirms it still needs a locker.
        locked = session_locked() if hyprlock else None
        if locked is False or (code == 0 and locked is not True) or (code > 0 and not hyprlock):
            return code
        if time.monotonic() - started >= LOCKER_HEALTHY_SECONDS:
            restarts = 0
        restarts += 1
        if restarts > LOCKER_MAX_RESTARTS and locked is not True:
            return code
        delay = LOCKER_RECOVERY_DELAY if restarts > LOCKER_MAX_RESTARTS else LOCKER_RESTART_DELAY
        log = options.get('stdout', sys.stderr)
        print(f'{datetime.now().isoformat(timespec="seconds")} Locker exited {code}; '
              f'locked={locked}, retry={restarts}, delay={delay}s', file=log, flush=True)
        time.sleep(delay)


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
    scope = settings.pop('effectWorkspaceScope', 'all')
    workspaces = settings.pop('effectWorkspaces', [])
    focus = settings.pop('blurFocus', 'both')
    rules = []
    def rule(match, **effects):
        rules.append({'name': 'hyprshell-glass-' + str(len(rules)), 'match': match, **effects})
    # Blur parameters are compositor-wide; dynamic rules restrict its visibility.
    if scope == 'selected':
        opacity_keys = ('activeOpacity', 'inactiveOpacity', 'fullscreenOpacity')
        opacity = [settings.get(k, 1) for k in opacity_keys]
        has_opacity = any(k in settings for k in opacity_keys)
        for key in opacity_keys:
            settings[key] = 1
        rule({'class': '.*'}, no_blur=True)
        for workspace in workspaces:
            match = {'workspace': str(workspace)}
            if has_opacity:
                rule(match, opacity=' '.join(str(v) + ' override' for v in opacity))
            if settings.get('blur') is not False:
                rule(match, no_blur=False)
    if focus != 'both' and settings.get('blur') is not False:
        rule({'focus': focus == 'unfocused'}, no_blur=True)
        if scope == 'all':
            rule({'focus': focus == 'focused'}, no_blur=False)
    if (scope == 'selected' or focus != 'both') and settings.get('blur') is not False:
        settings['blur'] = True
    sides = ('top', 'right', 'bottom', 'left')
    if any('gapsOut' + side.title() in settings for side in sides):
        settings['gapsOut'] = {side: settings.pop('gapsOut' + side.title(), settings.get('gapsOut', 10)) for side in sides}
    if not lua:
        def value_text(value):
            if isinstance(value, dict):
                return ','.join(str(value[side]) for side in sides)
            return str(value).lower()
        source = '# Generated by Hyprshell\n' + ''.join(f'{HYPR[k][0].replace(".", ":")} = {value_text(v)}\n' for k, v in settings.items())
        for row in rules:
            effects = [f'{k} {value_text(v)}' for k, v in row.items() if k not in ('name', 'match')]
            matches = [f'match:{k} {value_text(v)}' for k, v in row['match'].items()]
            source += 'windowrule = ' + ', '.join(effects + matches) + '\n'
        return source
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
    return '-- Generated by Hyprshell\nhl.config(' + encode(tree) + ')\n' + ''.join('hl.window_rule(' + encode(row) + ')\n' for row in rules)


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


def save(data, expected=None, *, toggle_workspace=None, app_action=None):
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
        if app_action is not None:
            data = application_action(current, app_action)
        if toggle_workspace is not None:
            data = copy.deepcopy(current)
            data['bar']['workspaceOverrides'][str(toggle_workspace)] = not bar_visible(current['bar'], toggle_workspace)
        # A shortcut can reveal a panel on a previously hidden workspace.
        data = validate(data)
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
    parser.add_argument('--app-action-json')
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
        if args.app_action_json:
            result = save(DEFAULTS, app_action=json.loads(args.app_action_json))
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
