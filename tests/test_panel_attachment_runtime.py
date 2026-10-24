"""Saved attachment is used on first construction; layout avoids contrast storms."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class PanelAttachmentRuntimeTests(unittest.TestCase):
    def test_saved_startup_and_wallpaper_toggle_cost(self):
        shell = (ROOT / 'config/quickshell/shell.qml').read_text()
        model = re.search(r'id: panels\s*\n(?:\s*//[^\n]*\n)*\s*model: ([^\n]+)', shell).group(1)
        fixture = '''import QtQuick
import Quickshell
import "."
import "SettingsModel.js" as Settings
import "AdaptiveColors.js" as Colors
ShellRoot {
    id: probe
    property int created: 0
    property int phase: 0
    SettingsStore { id: preferences }
    function check(ok, reason) {
        if (!ok) { console.error("ATTACHMENT_FAILED", reason); Qt.exit(1); }
    }
    Variants {
        id: panels
        model: MODEL
        FloatingWindow {
            required property var modelData
            implicitWidth: 1920; implicitHeight: 60
            visible: true
            Bar {
                id: bar
                width: 1920
                settings: preferences.panelConfig
                screenWidth: 1920; screenHeight: 1080
                wallpaperSource: "WALLPAPER"
                clockText: "October 25  04:54 AM  Sunday"
                statusData: ({workspaces:[{id:1,name:"1"}],audio:{text:"muted"},network:{},bluetooth:{},battery:{}})
            }
            Component.onCompleted: {
                probe.created++;
                probe.check(preferences.loaded, "surface created before preferences loaded");
                probe.check(bar.settings.bar.edgeAttached, "surface constructed detached");
                probe.check(Settings.screenMargins(bar.settings.bar).top === 0, "first-map margin");
            }
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    if (!bar.wallpaperColors.ready) return;
                    let calls = Colors.foregroundCalls;
                    let next = JSON.parse(JSON.stringify(preferences.config));
                    next.bar.edgeAttached = !next.bar.edgeAttached;
                    let started = Date.now();
                    preferences.acceptConfig(next);
                    let elapsed = Date.now() - started;
                    let searches = Colors.foregroundCalls - calls;
                    console.log("ATTACHMENT_TOGGLE", elapsed, searches);
                    probe.check(searches < 500, "layout eagerly solved connector contrast " + searches + " times");
                    if (++probe.phase === 4) { console.log("ATTACHMENT_OK"); Qt.quit(); }
                }
            }
        }
    }
    Timer { interval: 18000; running: true; onTriggered: { console.error("ATTACHMENT_TIMEOUT", probe.created); Qt.exit(2); } }
}
'''.replace('MODEL', model).replace('WALLPAPER', (ROOT / 'assets/wallpapers/default.jpg').as_uri())
        with tempfile.TemporaryDirectory(prefix='hyprshell-attachment-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            colors = payload / 'AdaptiveColors.js'
            source = colors.read_text().replace('function readableForeground(sample, accent, minimum, maximum, goal, minimumLightness) {',
                'var foregroundCalls = 0;\nfunction readableForeground(sample, accent, minimum, maximum, goal, minimumLightness) {\n    foregroundCalls++;')
            colors.write_text(source)
            saved = root / 'config/hyprshell/settings.json'
            saved.parent.mkdir()
            saved.write_text(json.dumps({'version': 1, 'bar': {
                'edgeAttached': True, 'fullBackground': 'on', 'uniformItems': True,
                'hyprknots': True, 'randomVibrantColors': True, 'fullPillTransparency': 30,
                'marginTop': 10, 'screenMarginTop': 0}}))
            entry = payload / 'Attachment.qml'
            entry.write_text(fixture)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=24)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('ATTACHMENT_OK', output)
            for error in ('ATTACHMENT_FAILED', 'ReferenceError', 'TypeError', 'Binding loop'):
                self.assertNotIn(error, output)
