"""Exercise the production icon catalog helper and its QML integration offscreen."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP_ICONS = ROOT / 'config/quickshell/AppIcons.qml'
COMMAND = '        command: ["python3", icons.helperPath, "--folders-json", JSON.stringify(icons.folders)]'


def variant(command=None, startup=None, restart=None):
    """Build a test copy with a controlled helper command or short timers."""
    source = APP_ICONS.read_text()
    if command is not None:
        if source.count(COMMAND) != 1:
            raise ValueError('AppIcons process command changed; review the integration test')
        source = source.replace(COMMAND, '        command: ' + json.dumps(command))
    if startup is not None:
        source = source.replace('        interval: 5000\n', '        interval: ' + str(startup) + '\n', 1)
    if restart is not None:
        source = source.replace('        interval: 30000\n', '        interval: ' + str(restart) + '\n', 1)
    return source


def environment(root):
    return dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                XDG_DATA_HOME=str(root / 'data'), XDG_DATA_DIRS=str(root / 'system-data'),
                QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')


def prepare(root):
    (root / 'runtime').mkdir(mode=0o700)
    (root / 'data/pixmaps').mkdir(parents=True)
    (root / 'system-data').mkdir()


def run(root, entry, on_line=None, timeout=20):
    """Run Quickshell while allowing the caller to react to output lines."""
    process = subprocess.Popen(
        ['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
        env=environment(root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1)
    output = []
    try:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError('Quickshell test timed out:\n' + ''.join(output))
            if select.select([process.stdout], [], [], min(remaining, 0.2))[0]:
                line = process.stdout.readline()
                if not line:
                    break
                output.append(line)
                if on_line:
                    on_line(line)
            elif process.poll() is not None:
                output.append(process.stdout.read())
                break
        code = process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        process.stdout.close()
    return code, ''.join(output)


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class AppIconsCatalogTests(unittest.TestCase):
    def assert_clean(self, code, output):
        self.assertEqual(code, 0, output)
        for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
            self.assertNotIn(error, output)

    def test_lazy_first_use_live_update_and_source_lookup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare(root)
            (root / 'data/pixmaps/hyprshell-test-icon.svg').write_text('icon')
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    id: root
    property int ticks: 0
    AppIcons { id: icons }
    function fail(message) { console.error('APP_ICONS_FAIL ' + message); Qt.exit(1); }
    Timer { interval: 150; running: true; onTriggered: {
        if (icons.catalogRequested) fail('Catalog started eagerly');
        let missed = icons.source('hyprshell-test-icon');
        if (missed !== '') fail('Lookup resolved before the catalog');
        if (!icons.catalogRequested) fail('First miss did not request the catalog');
        poll.start();
    }}
    Timer { id: poll; interval: 100; repeat: true; onTriggered: {
        root.ticks++;
        if (icons.catalog['hyprshell-test-icon'] !== undefined) {
            if (!icons.helperReady) fail('Helper never reported readiness');
            if (icons.useFolderModels) fail('Directory fallback engaged for a working helper');
            if (!icons.catalog['hyprshell-test-icon'].includes('/hyprshell-test-icon.svg'))
                fail('Catalog URL does not match FolderListModel formatting');
            if (!String(icons.source('hyprshell-test-icon')).includes('/hyprshell-test-icon.svg'))
                fail('Source did not use the helper catalog');
            console.log('APP_ICONS_FIRST_OK'); poll.stop(); live.start();
        }
        if (root.ticks > 120) fail('Timed out waiting for the first catalog');
    }}
    Timer { id: live; interval: 100; repeat: true; onTriggered: {
        if (icons.catalog['hyprshell-test-later'] !== undefined) {
            if (!String(icons.source('hyprshell-test-later')).includes('/hyprshell-test-later.png'))
                fail('Live update URL is wrong');
            console.log('APP_ICONS_LIVE_OK'); live.stop(); Qt.quit();
        }
    }}
    Timer { interval: 20000; running: true; onTriggered: fail('Test timed out') }
}
''')
            added = []

            def on_line(line):
                if 'APP_ICONS_FIRST_OK' in line and not added:
                    added.append(True)
                    (root / 'data/pixmaps/hyprshell-test-later.png').write_text('later')

            code, output = run(root, entry, on_line)
            self.assert_clean(code, output)
            self.assertIn('APP_ICONS_FIRST_OK', output)
            self.assertIn('APP_ICONS_LIVE_OK', output)

    def test_helper_start_failure_falls_back_to_directory_models(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare(root)
            (root / 'data/pixmaps/legacy-icon.svg').write_text('icon')
            (root / 'BrokenAppIcons.qml').write_text(variant(command=['/bin/false']))
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property int ticks: 0
    BrokenAppIcons { id: icons }
    function fail(message) { console.error('APP_ICONS_FAIL ' + message); Qt.exit(1); }
    Timer { interval: 100; running: true; onTriggered: {
        if (icons.source('legacy-icon') !== '') fail('Lookup resolved before the catalog');
        poll.start();
    }}
    Timer { id: poll; interval: 100; repeat: true; onTriggered: {
        root.ticks++;
        if (icons.catalog['legacy-icon'] !== undefined) {
            if (!icons.useFolderModels) fail('Directory fallback did not engage');
            if (icons.helperReady) fail('Failed helper reported readiness');
            if (!String(icons.source('legacy-icon')).includes('/legacy-icon.svg'))
                fail('Fallback catalog lookup failed');
            console.log('APP_ICONS_FALLBACK_OK'); Qt.quit();
        }
        if (root.ticks > 200) fail('Timed out waiting for the directory fallback');
    }}
    Timer { interval: 25000; running: true; onTriggered: fail('Test timed out') }
}
''')
            code, output = run(root, entry, timeout=28)
            self.assert_clean(code, output)
            self.assertIn('APP_ICONS_FALLBACK_OK', output)

    def test_silent_helper_times_out_to_directory_models(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare(root)
            (root / 'data/pixmaps/timeout-icon.svg').write_text('icon')
            (root / 'BrokenAppIcons.qml').write_text(
                variant(command=['sleep', '60'], startup=200))
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property int ticks: 0
    BrokenAppIcons { id: icons }
    function fail(message) { console.error('APP_ICONS_FAIL ' + message); Qt.exit(1); }
    Timer { interval: 50; running: true; onTriggered: {
        icons.source('timeout-icon'); poll.start();
    }}
    Timer { id: poll; interval: 100; repeat: true; onTriggered: {
        root.ticks++;
        if (icons.catalog['timeout-icon'] !== undefined) {
            if (!icons.useFolderModels) fail('Fallback did not engage after startup timeout');
            console.log('APP_ICONS_TIMEOUT_OK'); Qt.quit();
        }
        if (root.ticks > 200) fail('Timed out waiting for startup fallback');
    }}
    Timer { interval: 25000; running: true; onTriggered: fail('Test timed out') }
}
''')
            code, output = run(root, entry, timeout=28)
            self.assert_clean(code, output)
            self.assertIn('APP_ICONS_TIMEOUT_OK', output)

    def test_post_ready_exit_restarts_the_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare(root)
            counter = root / 'runs'
            script = root / 'stream.py'
            script.write_text('''import sys, time
with open(sys.argv[1], "a") as output:
    output.write("run\\n")
print('{"version":1,"revision":0,"catalog":{}}', flush=True)
time.sleep(0.25)
''')
            (root / 'BrokenAppIcons.qml').write_text(
                variant(command=['python3', str(script), str(counter)], restart=200))
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    BrokenAppIcons { id: icons }
    Timer { interval: 50; running: true; onTriggered: icons.source('restart-trigger') }
    Timer { interval: 1600; running: true; onTriggered: Qt.quit() }
}
''')
            code, output = run(root, entry)
            self.assert_clean(code, output)
            runs = counter.read_text().splitlines()
            self.assertGreaterEqual(len(runs), 2, 'Helper was not restarted after a post-ready exit')


if __name__ == '__main__':
    unittest.main()
