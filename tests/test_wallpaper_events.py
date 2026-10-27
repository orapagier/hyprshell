"""Exercise real inotify cache lifecycle without a compositor or daemon."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('wallpaper_events', ROOT / 'config/quickshell/helpers/wallpaper-events.py')
events = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(events)


class WallpaperEventsTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
    def test_native_event_query_and_poll_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            cache = root / 'cache/awww/version'
            cache.mkdir(parents=True)
            (cache / 'eDP-1').write_text('initial')
            (root / 'mode').write_text('initial')
            command = root / 'awww'
            command.write_text('''#!/usr/bin/python3
import os, pathlib
root = pathlib.Path(os.environ['WALLPAPER_TEST_ROOT'])
mode = (root / 'mode').read_text().strip()
print('eDP-1: 1920x1080, currently displaying: image: /tmp/' + mode + '.jpg')
''')
            command.chmod(0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "shell"
ShellRoot {
    WallpaperWatcher { id: watcher }
    FileView { id: mode; path: Quickshell.env('WALLPAPER_TEST_ROOT')+'/mode'; blockWrites: true }
    FileView { id: cache; path: Quickshell.env('XDG_CACHE_HOME')+'/awww/version/eDP-1'; blockWrites: true }
    TestCase { id: test; name:'WallpaperEvents'; when:false }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.tryCompare(watcher, 'eventsReady', true, 2000);
                test.tryVerify(() => watcher.sources['eDP-1'] === 'file:///tmp/initial.jpg', 2000);
                test.compare(watcher.poll.interval, 30000);
                mode.setText('external');
                cache.setText('external');
                test.tryVerify(() => watcher.sources['eDP-1'] === 'file:///tmp/external.jpg', 2000);
                test.compare(watcher.sources['eDP-1'], 'file:///tmp/external.jpg');
                mode.setText('uncached');
                // Accelerate only the watchdog clock; no filesystem event occurs.
                watcher.poll.interval = 100;
                watcher.poll.restart();
                test.tryVerify(() => watcher.sources['eDP-1'] === 'file:///tmp/uncached.jpg', 2000);
                test.compare(watcher.sources['eDP-1'], 'file:///tmp/uncached.jpg');
                watcher.events.running = false;
                test.tryCompare(watcher, 'eventsReady', false, 2000);
                console.log('WALLPAPER_EVENTS_OK'); Qt.quit();
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: Qt.exit(2) }
}
''')
            env = dict(os.environ, WALLPAPER_TEST_ROOT=str(root), PATH=str(root)+os.pathsep+os.environ['PATH'],
                       XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                       XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('WALLPAPER_EVENTS_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)

    def test_creation_replacement_removal_and_recreation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / 'awww'
            watcher = events.Watcher(cache, root)
            self.addCleanup(watcher.close)
            (root / 'unrelated').write_text('ignore')
            self.assertFalse(watcher.read_changes())
            version = cache / '0.12'
            version.mkdir(parents=True)
            self.assertTrue(watcher.read_changes())
            output = version / 'eDP-1'
            output.write_text('first')
            self.assertTrue(watcher.read_changes())
            replacement = version / 'temp'
            replacement.write_text('second')
            replacement.replace(output)
            self.assertTrue(watcher.read_changes())
            output.unlink()
            version.rmdir()
            cache.rmdir()
            self.assertTrue(watcher.read_changes())
            version.mkdir(parents=True)
            self.assertTrue(watcher.read_changes())
            output.write_text('third')
            self.assertTrue(watcher.read_changes())
            (root / 'wayland-1-awww-daemon.sock').touch()
            self.assertTrue(watcher.read_changes())

    def test_missing_cache_parent_is_discovered(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'missing' / 'awww'
            watcher = events.Watcher(cache)
            self.addCleanup(watcher.close)
            cache.mkdir(parents=True)
            self.assertTrue(watcher.read_changes())
            (cache / 'output').write_text('image')
            self.assertTrue(watcher.read_changes())


if __name__ == '__main__':
    unittest.main()
