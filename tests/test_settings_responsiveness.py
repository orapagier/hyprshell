"""Real UI previews remain immediate while isolated backend writes are slow."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class SettingsResponsivenessTests(unittest.TestCase):
    def test_preview_acknowledgement_failure_and_external_reload(self):
        fixture = '''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    property int savedChanges: 0
    property int panelChanges: 0
    property double started: 0
    property double settled: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: ui; store: prefs }
    Connections {
        target: prefs
        function onConfigChanged() { test.savedChanges++; }
        function onPanelConfigChanged() { test.panelChanges++; }
    }
    function audio(config) { return config.items.find(i => i.id === "audio"); }
    function check(ok, message) {
        if (!ok) { console.error("RESPONSIVE_FAILED", phase, message); Qt.exit(1); }
    }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && prefs.loaded) {
                ui.open();
                ui.section = ui.draft.items.findIndex(i => i.id === "audio");
                test.savedChanges = 0; test.panelChanges = 0;
                test.started = Date.now();
                ui.updateBar("position", "left");
                ui.updateBar("fullPillTransparency", 35);
                ui.updateItem("opacity", 0.7);
                test.phase = 1;
            } else if (test.phase === 1) {
                test.check(Date.now() - test.started < 200, "preview missed a frame before autosave");
                test.check(prefs.panelConfig.bar.position === "left", "edge preview");
                test.check(prefs.panelConfig.bar.fullPillTransparency === 35, "appearance preview");
                test.check(test.audio(prefs.panelConfig).opacity === 0.7, "item preview");
                test.check(test.audio(prefs.config).opacity === 1 && test.savedChanges === 0, "preview changed saved settings");
                test.phase = 2;
            } else if (test.phase === 2 && ui.saving) {
                test.check(Date.now() - test.started < 450, "save did not start promptly");
                ui.updateItem("opacity", 0.6);
                ui.visible = false;
                test.phase = 3;
            } else if (test.phase === 3) {
                test.check(test.audio(prefs.panelConfig).opacity === 0.6, "queued/closed preview reverted");
                if (!ui.dirty && !ui.saving) {
                    test.settled = Date.now(); test.phase = 4;
                }
            } else if (test.phase === 4 && Date.now() - test.settled > 250) {
                test.check(test.savedChanges === 2, "duplicate saved config publication: " + test.savedChanges);
                test.check(test.panelChanges === 4, "save repainted unchanged preview: " + test.panelChanges);
                // Same content and explicit reloads must be idempotent, while
                // actual external settings still propagate through FileView.
                prefs.acceptConfig(prefs.config); prefs.reload();
                test.settled = Date.now(); test.phase = 5;
            } else if (test.phase === 5 && Date.now() - test.settled > 150) {
                test.check(test.savedChanges === 2 && test.panelChanges === 4, "identical reload invalidated panel");
                ui.open();
                ui.updateItem("textColor", "#");
                test.phase = 6;
            } else if (test.phase === 6) {
                test.check(test.audio(prefs.panelConfig).textColor === "", "partial color previewed");
                if (!ui.success && !ui.saving) {
                    test.check(test.audio(prefs.config).textColor === "", "invalid color saved");
                    test.check(Object.keys(prefs.panelPreview).length === 0 && prefs.itemPreview === null, "failed preview retained");
                    external.running = true; test.phase = 7;
                }
            } else if (test.phase === 7 && test.audio(prefs.config).opacity === 0.8) {
                test.check(test.audio(prefs.panelConfig).opacity === 0.8, "external save not propagated");
                console.log("RESPONSIVE_OK"); Qt.quit();
            }
        }
    }
    Process {
        id: external
        command: ["python3", "-c", "import json,os; from pathlib import Path; p=Path(os.environ['XDG_CONFIG_HOME'])/'hyprshell/settings.json'; d=json.loads(p.read_text()); next(i for i in d['items'] if i['id']=='audio')['opacity']=0.8; p.write_text(json.dumps(d))"]
    }
    Timer { interval: 12000; running: true; onTriggered: { console.error("RESPONSIVE_TIMEOUT", test.phase, ui.message); Qt.exit(2); } }
}
'''.replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\n')
        with tempfile.TemporaryDirectory(prefix='hyprshell-responsive-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'Responsive.qml'
            entry.write_text(fixture)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            commands = root / 'bin'
            commands.mkdir()
            wrapper = commands / 'python3'
            wrapper.write_text(f'#!{sys.executable}\nimport os,sys,time\ntime.sleep(0.4)\n'
                               f'os.execv({sys.executable!r}, [{sys.executable!r}] + sys.argv[1:])\n')
            wrapper.chmod(0o755)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=16)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('RESPONSIVE_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)
