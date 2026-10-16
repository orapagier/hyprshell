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

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'config/quickshell'
EDGES = ('top', 'bottom', 'left', 'right')


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
import "PAYLOAD"
ShellRoot {
    SettingsStore { id: preferences }
    ApplicationService { id: apps; store: preferences; windows: []; entries: [] }
    DockUtilities { id: utilityService }
    Variants {
        model: Quickshell.screens.filter(s => s.name === Quickshell.env('HYPRSHELL_TEST_OUTPUT'))
        Item {
            required property var modelData
            DockWindow { output: modelData; service: apps; config: preferences.config; utilities: utilityService }
            DockWindow { component: 'hyprbar'; output: modelData; service: apps; config: preferences.config; utilities: utilityService }
        }
    }
}
'''


def layers(output, pid):
    data = json.loads(hypr('-j', 'layers')).get(output, {}).get('levels', {})
    return [layer for level in data.values() for layer in level
            if layer.get('pid') == pid and layer['namespace'] in
            ('hyprshell-dock', 'hyprshell-taskbar')]


def check_geometry(rows, output, case):
    width = round(output['width'] / output['scale'])
    height = round(output['height'] / output['scale'])
    by_name = {row['namespace']: row for row in rows}
    for namespace, edge in zip(('hyprshell-dock', 'hyprshell-taskbar'), case):
        row = by_name[namespace]
        x, y = row['x'] - output['x'], row['y'] - output['y']
        w, h = row['w'], row['h']
        assert w > 0 and h > 0, row
        assert x >= 0 and y >= 0 and x+w <= width and y+h <= height, row
        assert (h == 32 if edge in ('top', 'bottom') else w == 32), row
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
            fixture = root / 'Check.qml'
            fixture.write_text(QML.replace('PAYLOAD', PAYLOAD.as_uri()))
            config = json.loads((PAYLOAD / 'settings/defaults.json').read_text())
            config['panels']['hyprpane']['enabled'] = False
            for name in ('hyprdock', 'hyprbar'):
                config['panels'][name].update(enabled=True, monitors=[output['name']],
                                             hideMode='always', animations=False)
            cases = list(itertools.permutations(EDGES, 2))
            print(f"Live output: {output['width']}x{output['height']} scale={output['scale']}", flush=True)
            for index, case in enumerate(cases):
                for name, edge in zip(('hyprdock', 'hyprbar'), case):
                    config['panels'][name]['position'] = edge
                # Atomic replacement lets SettingsStore watch each case safely.
                pending = target.with_suffix('.tmp')
                pending.write_text(json.dumps(config))
                pending.replace(target)
                if process is None:
                    env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                               XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='wayland',
                               QT_QPA_PLATFORMTHEME='', HYPRSHELL_TEST_OUTPUT=output['name'])
                    log = (root / 'quickshell.log').open('w+')
                    process = subprocess.Popen(['quickshell', '-p', str(fixture)], env=env,
                                               stdout=log, stderr=subprocess.STDOUT)
                def ready():
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    current = next(m for m in monitors() if m['name'] == output['name'])
                    rows = layers(output['name'], process.pid)
                    if len(rows) != 2:
                        return False
                    try:
                        check_geometry(rows, current, case)
                    except AssertionError:
                        return False
                    return rows
                try:
                    wait_for(ready, 'dock/taskbar geometry ' + '/'.join(case))
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
                print(f'PASS {index+1}/12 dock={case[0]} taskbar={case[1]}', flush=True)
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
    print('Live dock/taskbar layer geometry passed; temporary output removed.')


if __name__ == '__main__':
    main()
