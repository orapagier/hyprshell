"""Exercise external labels and helper failure/recovery with isolated native Qt."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class AuditHardeningTests(unittest.TestCase):
    def test_labels_weather_failures_and_wallpaper_recovery(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-audit-') as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            executable = root / 'awww'
            executable.write_text('''#!/usr/bin/python3
import os, pathlib, sys
mode = (pathlib.Path(os.environ['AUDIT_TEST_ROOT']) / 'mode').read_text().strip()
if mode != 'empty':
    print('eDP-1: 1920x1080, currently displaying: image: /tmp/' + mode + '.jpg')
sys.exit(1 if mode == 'failed' else 0)
''')
            executable.chmod(0o700)
            (root / 'mode').write_text('initial')
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "shell"
ShellRoot {
    WallpaperWatcher { id: watcher }
    FileView { id: mode; path: Quickshell.env("AUDIT_TEST_ROOT") + "/mode" }
    FloatingWindow {
        visible: true; implicitWidth: 400; implicitHeight: 700
        MenuButton { id: button; text: "<b>Untrusted network</b>" }
        AppListButton { id: app; visible: false; text: "<b>Untrusted app</b>" }
        SettingsButton { id: setting; visible: false; text: button.text }
        SettingsCheckBox { id: checkbox; visible: false; text: button.text }
        SettingsSwitch { id: toggle; visible: false; text: button.text }
        SettingsComboBox { id: combo; model: [button.text] }
        WeatherCard { id: weather; y: 50; width: 380; helperProgram: "/usr/bin/false" }
    }
    TestCase { id: test; name: "AuditHardening"; when: false }
    function query(value) {
        mode.setText(value);
        mode.waitForJob();
        watcher.query.running = true;
        test.tryCompare(watcher.query, "running", false, 2000);
        watcher.poll.stop();
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.tryCompare(watcher.query, "running", false, 2000);
                watcher.poll.stop();
                test.compare(watcher.sources['eDP-1'], 'file:///tmp/initial.jpg');
                let original = watcher.sources;
                query('failed');
                test.compare(watcher.sources, original);
                test.compare(watcher.retryInterval, 4000);
                for (let i = 0; i < 5; i++) query('failed');
                test.compare(watcher.retryInterval, 30000);
                query('recovered');
                test.compare(watcher.sources['eDP-1'], 'file:///tmp/recovered.jpg');
                test.compare(watcher.retryInterval, 2000);
                query('empty');
                test.compare(Object.keys(watcher.sources).length, 0);
                test.compare(button.contentItem.textFormat, Text.PlainText);
                test.compare(button.contentItem.text, '<b>Untrusted network</b>');
                for (let control of [setting, checkbox, toggle, combo])
                    test.compare(control.contentItem.textFormat, Text.PlainText);
                let appLabel = app.contentItem.children[1];
                test.compare(appLabel.text, '<b>Untrusted app</b>');
                test.compare(appLabel.textFormat, Text.PlainText);
                combo.popup.open();
                test.tryVerify(() => combo.popup.contentItem.itemAtIndex(0) !== null);
                test.compare(combo.popup.contentItem.itemAtIndex(0).contentItem.textFormat, Text.PlainText);
                combo.popup.close();
                weather.editing = true;
                weather.results = [{name:'<b>Untrusted place</b>', latitude:10, longitude:120}];
                test.wait(50);
                let choice = test.findChild(weather, 'weatherResult-0');
                test.verify(choice !== null);
                test.compare(choice.contentItem.textFormat, Text.PlainText);
                test.compare(choice.contentItem.text, '<b>Untrusted place</b>');
                weather.search();
                test.tryCompare(weather, 'busy', false, 2000);
                test.tryCompare(weather, 'message', 'Could not search for places. Try again.', 2000);
                weather.selectLocation({name:'Place', latitude:10, longitude:120});
                test.tryCompare(weather, 'busy', false, 2000);
                test.tryCompare(weather, 'message', 'Could not save location. Try again.', 2000);
                console.log('AUDIT_HARDENING_OK'); Qt.quit();
            } catch (error) { console.error(error, error.stack); Qt.exit(1); }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: Qt.exit(2) }
}
''')
            env = dict(os.environ, AUDIT_TEST_ROOT=str(root), PATH=str(root) + os.pathsep + os.environ['PATH'],
                       XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('AUDIT_HARDENING_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)


if __name__ == '__main__':
    unittest.main()
