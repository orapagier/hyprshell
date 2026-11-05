#!/usr/bin/env python3
"""Profile the retained FolderListModel fallback in a temporary offscreen copy.

The helper is intentionally disabled in the copy so this tool keeps measuring
the original per-directory fan-out. It never edits live QML.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from measure_shell import tree_sample

ROOT = Path(__file__).resolve().parents[1]
MARKER = 'ICON_PROFILE '


def instrument(source):
    anchor = '    function rebuild() {\n'
    request = 'Qt.callLater(icons.rebuild)'
    helper = '    property bool useFolderModels: false\n'
    if source.count(anchor) != 1 or source.count(request) != 3 or source.count(helper) != 1:
        raise ValueError('AppIcons structure changed; review instrumentation before profiling')
    # Keep the original fan-out reproducible now that the helper is production.
    source = source.replace(helper, '    property bool useFolderModels: true\n')
    source = source.replace(request, 'icons.profileRequest()')
    source = source.replace(anchor, '''    property int profileRequests: 0
    property int profileRebuilds: 0
    property var profileEvents: []
    function profileRequest() {
        profileRequests++;
        profileEvents.push({kind: "request", time: Date.now(), batch: profileRebuilds});
        Qt.callLater(icons.rebuild);
    }
    function profileState() {
        let ready = 0;
        for (let i = 0; i < directories.count; i++)
            if (directories.objectAt(i)?.status === FolderListModel.Ready) ready++;
        return {requests: profileRequests, rebuilds: profileRebuilds,
                directories: directories.count, ready: ready,
                entries: Object.keys(catalog).length, events: profileEvents};
    }
    function rebuild() {
        profileRebuilds++;
        profileEvents.push({kind: "rebuild", time: Date.now(), batch: profileRebuilds});
''')
    return source


ENTRY = '''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property int stable: 0
    property int lastRebuild: -1
    AppIcons { id: icons }
    Timer { interval: 300; running: true; onTriggered: console.log('ICON_PROFILE before') }
    Timer { interval: 800; running: true; onTriggered: {
        console.log('ICON_PROFILE miss');
        icons.source('hyprshell-profiling-intentionally-missing-icon');
        settle.start();
    }}
    Timer { id: settle; interval: 100; repeat: true; onTriggered: {
        if (root.lastRebuild === icons.profileRebuilds) root.stable++;
        else root.stable = 0;
        root.lastRebuild = icons.profileRebuilds;
        if (root.stable >= 5) {
            stop();
            console.log('ICON_PROFILE result ' + JSON.stringify(icons.profileState()));
            exitDelay.start();
        }
    }}
    Timer { id: exitDelay; interval: 1000; onTriggered: Qt.quit() }
    Timer { interval: 15000; running: true; onTriggered: Qt.exit(2) }
}
'''


def capture(source):
    with tempfile.TemporaryDirectory(prefix='hyprshell-icon-profile-') as directory:
        root = Path(directory)
        (root / 'runtime').mkdir(mode=0o700)
        (root / 'AppIcons.qml').write_text(instrument(source))
        (root / 'Profile.qml').write_text(ENTRY)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'),
                   XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'),
                   HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORM='offscreen',
                   QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
        command = ['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Profile.qml')]
        report = {'mode': 'legacy-folder-models', 'snapshots': {}}
        # A file avoids pipe backpressure; bounded polling only belongs to this profiler.
        with (root / 'log').open('w') as writer, (root / 'log').open() as log:
            with subprocess.Popen(command, env=env, stdout=writer, stderr=subprocess.STDOUT) as child:
                try:
                    offset = 0
                    deadline = time.monotonic() + 18
                    while time.monotonic() < deadline:
                        log.seek(offset)
                        lines = log.readlines()
                        offset = log.tell()
                        for line in lines:
                            if MARKER not in line:
                                continue
                            event = line.split(MARKER, 1)[1].strip()
                            if event in ('before', 'miss'):
                                report['snapshots'][event] = tree_sample(child.pid)
                            elif event.startswith('result '):
                                report['catalog'] = json.loads(event[len('result '):])
                                report['snapshots']['after'] = tree_sample(child.pid)
                        if child.poll() is not None:
                            break
                        time.sleep(0.01)
                    else:
                        raise ValueError('Icon profile timed out')
                    if child.returncode != 0 or 'catalog' not in report or len(report['snapshots']) != 3:
                        log.seek(0)
                        raise ValueError('Icon profile failed: ' + log.read()[-4000:])
                finally:
                    if child.poll() is None:
                        child.terminate()
                        try:
                            child.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait()
        before = list(report['snapshots']['before']['processes'].values())
        after = list(report['snapshots']['after']['processes'].values())
        report['thread_delta'] = sum(len(r['threads']) for r in after) - sum(len(r['threads']) for r in before)
        report['fd_delta'] = (sum(r['fds'] for r in after) - sum(r['fds'] for r in before)
                              if all(r['fds'] is not None for r in before + after) else None)
        report['complete'] = all(not s['errors'] for s in report['snapshots'].values())
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.runs <= 10:
        parser.error('--runs must be 1–10')
    source = (ROOT / 'config/quickshell/AppIcons.qml').read_text()
    with args.output.open('x') as output:
        result = {'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
                  'mode': 'legacy-folder-models',
                  'limits': 'Isolated offscreen copy with the helper disabled; measures the retained '
                            'FolderListModel fallback. Instrumentation affects timing. Rebuild batch IDs are '
                            'callLater callback boundaries, not a global event-loop turn counter. '
                            'No real icon-ready latency or desktop first-miss CPU acceptance claim.',
                  'runs': [capture(source) for _ in range(args.runs)]}
        json.dump(result, output, indent=2)
        output.write('\n')
    for run in result['runs']:
        print(json.dumps({k: run[k] for k in ('thread_delta', 'fd_delta', 'complete')} |
                         {k: run['catalog'][k] for k in ('requests', 'rebuilds', 'directories', 'ready', 'entries')}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
