#!/usr/bin/env python3
"""Opt-in layer-shell smoke check on a temporary live Hyprland headless output."""
import argparse
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
if __package__:
    from .panel_live_behavior import QML_CONTROL, run_behavior, write_json
else:
    from panel_live_behavior import QML_CONTROL, run_behavior, write_json

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'config/quickshell'
EDGES = ('top', 'bottom', 'left', 'right')
NAMESPACES = {'hyprpane': 'hyprshell', 'hyprdock': 'hyprshell-dock',
              'hyprbar': 'hyprshell-taskbar'}


def hypr(*args):
    return subprocess.check_output(['hyprctl', *args], text=True, timeout=5)


def monitors():
    return json.loads(hypr('-j', 'monitors'))


def wait_for(check, description):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.1)
    raise RuntimeError('Timed out: ' + description)


QML = '''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "PAYLOAD"
import "PAYLOAD/SettingsModel.js" as Settings
import "PAYLOAD/DockModel.js" as DockModel
ShellRoot {
    id: shell
    property var services: ({audioIcon:'',statusData: shell.statusData})
    property var inbox: null
    property var statusData: ({workspaces:[],audio:{},network:{},bluetooth:{},battery:{}})
    property var mediaData: ({playing:false,levels:[],title:'',tooltip:''})
    property var notificationData: ({count:0})
    property string clockText: '12:00'
    SettingsStore { id: preferences }
    ApplicationService { id: applications; store: preferences; windows: shell.control.windows || []; entries: [] }
    DockUtilities { id: dockUtilities }
    QtObject { id: wallpapers; property var sources: ({}) }
    QtObject { id: tray; property var items: [] }
    QtObject { id: settingsController; function open() {} }
PANELS
CONTROL
}
'''


def fixture_source():
    # Exercise the exact production composition, including Hyprpane's inline
    # PanelWindow, rather than maintaining another copy of its placement logic.
    source = (PAYLOAD / 'shell.qml').read_text()
    start = source.index('    Variants {\n        id: panels\n')
    end = source.index('    Connections {\n        target: preferences\n', start)
    panels = source[start:end]
    if panels.count('model: Quickshell.screens\n') != 3:
        raise RuntimeError('Production panel composition changed; review the live fixture')
    panels = panels.replace('model: Quickshell.screens\n',
                            "model: Quickshell.screens.filter(s => s.name === Quickshell.env('HYPRSHELL_TEST_OUTPUT'))\n")
    return QML.replace('PANELS', panels).replace('CONTROL', QML_CONTROL).replace('PAYLOAD', PAYLOAD.as_uri())


def layers(output, pid):
    monitor = next(m for m in monitors() if m['name'] == output)
    size = (round(monitor['width'] / monitor['scale']),
            round(monitor['height'] / monitor['scale']))
    data = json.loads(hypr('-j', 'layers')).get(output, {}).get('levels', {})
    return [layer for level in data.values() for layer in level
            if layer.get('pid') == pid and layer['namespace'] in
            NAMESPACES.values() and (layer['w'], layer['h']) != size]


def check_geometry(rows, output, case, pair=('hyprdock', 'hyprbar')):
    width = round(output['width'] / output['scale'])
    height = round(output['height'] / output['scale'])
    by_name = {row['namespace']: row for row in rows}
    assert len(rows) == 2 and set(by_name) == {NAMESPACES[name] for name in pair}, rows
    for component, edge in zip(pair, case):
        namespace = NAMESPACES[component]
        row = by_name[namespace]
        x, y = row['x'] - output['x'], row['y'] - output['y']
        w, h = row['w'], row['h']
        assert w > 0 and h > 0, row
        assert x >= 0 and y >= 0 and x+w <= width and y+h <= height, row
        thickness = h if edge in ('top', 'bottom') else w
        # Hyprpane grows to fit its enabled controls; app rails are fixed size.
        assert (32 <= thickness <= 80 if component == 'hyprpane' else thickness == 32), row
        if edge == 'top':
            assert y <= 80, row
        elif edge == 'bottom':
            assert height - y - h <= 80, row
        elif edge == 'left':
            assert x <= 80, row
        else:
            assert width - x - w <= 80, row
    a, b = rows
    assert not (a['x'] < b['x']+b['w'] and a['x']+a['w'] > b['x']
                and a['y'] < b['y']+b['h'] and a['y']+a['h'] > b['y']), rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true', help='create and remove a temporary virtual output')
    parser.add_argument('--checks', choices=('geometry', 'behavior', 'all'), default='geometry',
                        help='include visibility, menus and reservation checks with injected window data')
    args = parser.parse_args()
    if not __debug__:
        parser.error('run without Python optimization so geometry assertions remain enabled')
    if not args.run:
        parser.error('--run is required; this check briefly adds a live virtual output')
    before = {m['name'] for m in monitors()}
    output = None
    process = None
    try:
        hypr('output', 'create', 'headless')
        added = wait_for(lambda: [m for m in monitors() if m['name'] not in before], 'virtual output')
        if len(added) != 1:
            raise RuntimeError('Cannot uniquely identify the temporary output')
        output = added[0]
        with tempfile.TemporaryDirectory(prefix='hyprshell-panel-live-') as directory:
            root = Path(directory)
            target = root / 'config/hyprshell/settings.json'
            target.parent.mkdir(parents=True)
            control = root / 'control.json'
            control.write_text('{}')
            fixture = root / 'Check.qml'
            fixture.write_text(fixture_source())
            config = json.loads((PAYLOAD / 'settings/defaults.json').read_text())
            for name in NAMESPACES:
                config['panels'][name].update(enabled=False, monitors=[output['name']])
                if name != 'hyprpane':
                    config['panels'][name].update(hideMode='always', animations=False)
            cases = list(itertools.product(itertools.combinations(NAMESPACES, 2),
                                           itertools.permutations(EDGES, 2)))
            if args.checks == 'behavior':
                cases = []
            write_json(target, config)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='wayland',
                       QT_QPA_PLATFORMTHEME='', HYPRSHELL_TEST_OUTPUT=output['name'],
                       HYPRSHELL_TEST_CONTROL=str(control))
            log = (root / 'quickshell.log').open('w+')
            process = subprocess.Popen(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            print(f"Live output: {output['width']}x{output['height']} scale={output['scale']}", flush=True)
            for index, (pair, case) in enumerate(cases):
                for name in NAMESPACES:
                    config['panels'][name]['enabled'] = name in pair
                for name, edge in zip(pair, case):
                    if name == 'hyprpane':
                        config['bar']['position'] = edge
                    else:
                        config['panels'][name]['position'] = edge
                # Atomic replacement lets SettingsStore watch each case safely.
                pending = target.with_suffix('.tmp')
                pending.write_text(json.dumps(config))
                pending.replace(target)
                def ready():
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    current = next(m for m in monitors() if m['name'] == output['name'])
                    rows = layers(output['name'], process.pid)
                    if len(rows) != 2:
                        return False
                    try:
                        check_geometry(rows, current, case, pair)
                    except (AssertionError, KeyError):
                        return False
                    return rows
                try:
                    wait_for(ready, 'panel geometry ' + str(dict(zip(pair, case))))
                    # Require a second settled sample after the compositor has
                    # processed anchor and exclusive-zone changes.
                    time.sleep(.2)
                    if not ready():
                        raise RuntimeError('Geometry did not remain stable')
                except RuntimeError:
                    log.seek(0)
                    print(log.read())
                    print(json.dumps({'output': next(m for m in monitors() if m['name'] == output['name']),
                                      'layers': layers(output['name'], process.pid)}))
                    raise
                print(f'PASS {index+1}/{len(cases)} {dict(zip(pair, case))}', flush=True)
            if args.checks in ('behavior', 'all'):
                try:
                    run_behavior(config, target, control, log, process, output, hypr, monitors, wait_for)
                except Exception:
                    log.seek(0)
                    print(log.read())
                    raise
            process.terminate()
            process.wait(timeout=5)
            log.seek(0)
            contents = log.read()
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                if error in contents:
                    raise RuntimeError(contents)
            log.close()
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        if output is not None:
            hypr('output', 'remove', output['name'])
            wait_for(lambda: output['name'] not in {m['name'] for m in monitors()}, 'output removal')
    print(f'Live {args.checks} checks passed; temporary output removed.')


if __name__ == '__main__':
    main()
