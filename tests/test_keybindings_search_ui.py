"""Exercise the shortcut menu with real Qt keyboard events and inert process I/O."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]


class KeybindingsSearchTests(unittest.TestCase):
    def test_search_selection_keeps_typing_focus(self):
        source = r'''import QtQuick
import QtQuick.Window
import QtTest
import "."
Item {
        width: 560; height: 500
        KeybindingsMenu { id: menu; anchors.fill: parent }
        TestCase {
            name: "KeybindingsSearch"
            when: windowShown
            function keyClicks(text) { for (let c of text) keyClick(c); }
            function test_keyboard_search() {
                let search = findChild(menu, "keybindingsSearch");
                let list = findChild(menu, "keybindingsList");
                verify(search !== null && list !== null);
                search.forceActiveFocus();
                tryCompare(search, "activeFocus", true);
                keyClicks("kitty");
                compare(menu.entries.length, 2);
                compare(list.currentIndex, 0);
                tryVerify(() => list.currentItem !== null);
                verify(list.currentItem.highlighted);
                keyClick(Qt.Key_Down);
                compare(list.currentIndex, 1);
                verify(search.activeFocus);
                verify(list.currentItem.highlighted);
                menu.bindings = []; // Periodic refresh must preserve browsing position.
                compare(list.currentIndex, 1);
                keyClick(Qt.Key_Down);
                compare(list.currentIndex, 1);
                keyClick(Qt.Key_Up);
                compare(list.currentIndex, 0);
                keyClick(Qt.Key_Up);
                compare(list.currentIndex, 0);
                keyClick(Qt.Key_Down);
                keyClicks(" copy");
                compare(search.text, "kitty copy");
                compare(menu.entries.length, 1);
                compare(list.currentIndex, 0);
                verify(search.activeFocus);
                verify(list.currentItem.highlighted);
                keyClicks(" zzznomatch");
                compare(menu.entries.length, 0);
                compare(list.currentIndex, -1);
                keyClick(Qt.Key_Down);
                keyClick(Qt.Key_Up);
                compare(list.currentIndex, -1);
                verify(search.activeFocus);
                search.clear();
                compare(list.currentIndex, 0);
                verify(menu.entries.length > 2);
                for (let i = 0; i < menu.entries.length + 2; ++i) keyClick(Qt.Key_Down);
                compare(list.currentIndex, menu.entries.length - 1);
                verify(search.activeFocus);
                tryVerify(() => list.contentY > 0);
                keyClicks("kitty");
                compare(list.currentIndex, 0);
                tryVerify(() => list.atYBeginning);
                verify(search.activeFocus);
            }
        }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / 'config/quickshell'
            payload.mkdir(parents=True)
            for name in ('KeybindingsMenu.qml', 'KeybindingsGuide.js', 'AdaptiveColors.js'):
                shutil.copy2(ROOT / 'config/quickshell' / name, payload / name)
            # Stub only background process I/O; test the unchanged menu and search code.
            module = root / 'imports/Quickshell/Io'
            module.mkdir(parents=True)
            (module / 'qmldir').write_text('module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n')
            (module / 'Process.qml').write_text('import QtQuick\nQtObject { property var command; property bool running: false; property QtObject stdout; signal exited(int code, int status) }\n')
            (module / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property string text; signal streamFinished() }\n')
            entry = payload / 'tst_Search.qml'
            entry.write_text(source)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            runner = subprocess.check_output([sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
            result = subprocess.run([runner, '-import', str(root / 'imports'), '-input', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('KeybindingsSearch::test_keyboard_search()', output, output)
            for error in ('FAIL!', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output, output)


if __name__ == '__main__':
    unittest.main()
