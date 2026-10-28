"""Exercise Settings wallpaper adaptation in native Qt without desktop writes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class SettingsWallpaperTests(unittest.TestCase):
    def test_wallpaper_switch_output_filter_cache_accessibility_and_reopen(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            for name, color in [('blue', '#184477'), ('red', '#771844'),
                                ('white', '#ffffff'), ('black', '#000000')]:
                (root / (name + '.svg')).write_text(
                    f'<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600">'
                    f'<path fill="{color}" d="M0 0h800v600H0z"/></svg>')
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
import "shell/style" as Style
import "shell/AdaptiveColors.js" as Colors
ShellRoot {
    id: root
    property int captures: 0
    property string base: "file://" + Quickshell.env("WALLPAPER_TEST_ROOT") + "/"
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    TestCase { id: test; name: "SettingsWallpaper"; when: false }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            let result = find(child, name);
            if (result) return result;
        }
        return null;
    }
    function wallpaper(name) {
        let sources = {};
        sources[controller.window.screen.name] = root.base + name + ".svg";
        controller.wallpaperSources = sources;
    }
    function readable() {
        for (let fill of [Style.SettingsTheme.background, Style.SettingsTheme.sidebar,
                Style.SettingsTheme.surface, Style.SettingsTheme.field,
                Style.SettingsTheme.button, Style.SettingsTheme.hover,
                Style.SettingsTheme.pressed, Style.SettingsTheme.selection]) {
            test.verify(Colors.contrast(Style.SettingsTheme.text, fill) >= 4.5, "text contrast");
            test.verify(Colors.contrast(Style.SettingsTheme.muted, fill) >= 4.5, "secondary contrast");
        }
        for (let fill of [Style.SettingsTheme.accent, Style.SettingsTheme.accentHover,
                Style.SettingsTheme.accentPressed])
            test.verify(Colors.contrast(Style.SettingsTheme.accentForeground, fill) >= 4.5, "accent contrast");
        test.verify(Colors.contrast(Style.SettingsTheme.controlBorder, Style.SettingsTheme.field) >= 3,
                    "control outline contrast");
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.tryCompare(prefs, "loaded", true, 3000);
                controller.open();
                let editor = controller.window;
                root.wallpaper("blue");
                let sampler = root.find(editor.contentItem, "settingsWallpaperSampler");
                test.verify(!!sampler);
                test.tryCompare(sampler, "ready", true, 3000);
                test.verify(Style.SettingsTheme.background.b > Style.SettingsTheme.background.r);
                root.readable();
                let background = Style.SettingsTheme.background.toString();
                let accent = Style.SettingsTheme.accent.toString();
                let sources = Object.assign({}, controller.wallpaperSources);
                sources["other-output"] = root.base + "red.svg";
                controller.wallpaperSources = sources;
                test.wait(150);
                test.compare(Style.SettingsTheme.background.toString(), background);
                sampler.pixelsChanged.connect(() => root.captures++);
                editor.implicitWidth -= 100;
                editor.implicitHeight -= 80;
                editor.section = -2;
                test.wait(150);
                test.compare(root.captures, 0, "resizing/navigation must reuse samples");
                root.wallpaper("red");
                test.tryVerify(() => sampler.ready && Style.SettingsTheme.background.r > Style.SettingsTheme.background.b, 3000);
                test.verify(Style.SettingsTheme.accent.toString() !== accent);
                test.compare(editor.color, Style.SettingsTheme.background);
                root.readable();
                for (let name of ["white", "black"]) {
                    root.wallpaper(name);
                    test.tryVerify(() => sampler.ready && sampler.source.toString().endsWith(name + ".svg"), 3000);
                    root.readable();
                }
                root.wallpaper("red");
                test.tryVerify(() => sampler.ready && Style.SettingsTheme.background.r > Style.SettingsTheme.background.b, 3000);
                background = Style.SettingsTheme.background.toString();
                Style.Theme.preferences = {highContrast: true, textScale: 1.5, reducedMotion: true};
                test.compare(Style.SettingsTheme.background, Qt.color("#000000"));
                test.compare(Style.SettingsTheme.bodySize, 21);
                test.compare(Style.SettingsTheme.duration(null, 200), 0);
                root.readable();
                Style.Theme.preferences = {};
                test.compare(Style.SettingsTheme.background.toString(), background);
                controller.wallpaperSources = {};
                test.tryCompare(sampler, "ready", false, 1000);
                root.readable();
                editor.visible = false;
                test.tryCompare(controller, "loaded", false, 3000);
                controller.open();
                root.wallpaper("blue");
                test.tryVerify(() => Style.SettingsTheme.background.b > Style.SettingsTheme.background.r
                    && root.find(controller.window.contentItem, "settingsWallpaperSampler").ready, 3000);
                test.compare(controller.window.color, Style.SettingsTheme.background);
                root.readable();
                console.log("SETTINGS_WALLPAPER_OK"); Qt.quit();
            } catch (error) { console.error(error, error.stack); Qt.exit(1); }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: Qt.exit(2) }
}
''')
            env = dict(os.environ, WALLPAPER_TEST_ROOT=str(root),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SETTINGS_WALLPAPER_OK', output)
            for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop', 'FAIL!'):
                self.assertNotIn(error, output)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists(),
                             'Wallpaper changes must not save preferences')
