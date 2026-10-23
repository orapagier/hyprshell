"""Exercise the centered launcher and its production dropdown integration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class LauncherPopupTests(unittest.TestCase):
    def test_centered_card_search_launch_dismiss_and_reopen(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'shell'
            payload.mkdir()
            for source in (ROOT / 'config/quickshell').iterdir():
                if source.name != 'Dropdown.qml':
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            # Offscreen Qt has no layer-shell backend. Keep production routing,
            # content and input geometry, with a floating surface for the test.
            source = (ROOT / 'config/quickshell/Dropdown.qml').read_text()
            source = source.replace('PanelWindow {', 'FloatingWindow {', 1)
            source = source.replace('WlrLayershell.keyboardFocus:', 'property int testKeyboardFocus:')
            source = '\n'.join(line for line in source.splitlines() if not any(
                token in line for token in ('anchors { top:', 'exclusionMode:', 'mask: Region', 'WlrLayershell.')))
            (payload / 'Dropdown.qml').write_text(source)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import "shell"
ShellRoot {
    id: root
    property var launched: []
    QtObject {
        id: apps
        property var entries: [
            {id:"alpha.desktop",name:"Alpha",genericName:"Keyboard check",icon:""},
            {id:"beta.desktop",name:"Beta",genericName:"Keyboard check",icon:""}
        ]
        function launch(entry) { root.launched.push(entry.id); return true; }
        function iconSource(icon) { return ""; }
    }
    Dropdown {
        id: dropdown
        implicitWidth: 1000; implicitHeight: 800
        services: ({})
        inbox: ({})
        applicationService: apps
        onCloseRequested: section = ""
    }
    FloatingWindow {
        visible: true; implicitWidth: 1000; implicitHeight: 800
        LauncherPopup {
            id: popup
            width: parent.width; height: parent.height
            applicationService: apps
            onCloseRequested: opened = false
        }
    }
    TestCase { id: input; when: false }
    function check(ok, message) { if (!ok) throw new Error(message); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(input.findChild(popup, 'launcherSearch') === null, "Closed launcher releases contents");
                popup.opened = true;
                input.wait(50);
                let card = input.findChild(popup, 'launcherCard');
                check(card.width === 520 && card.height === 600, "Card matches Super+K dimensions");
                check(card.x === 240 && card.y === 100 && card.radius === 22, "Card centered with rounded corners");
                popup.width = 420; popup.height = 560;
                input.wait(30);
                check(card.width === 380 && card.height === 520 && card.x === 20 && card.y === 20, "Card fits smaller screens");
                popup.width = 1000; popup.height = 800;
                input.wait(30);
                let search = input.findChild(popup, 'launcherSearch');
                let list = input.findChild(popup, 'applicationsList');
                check(search.activeFocus && search.height === 46, "Search starts focused with matching height");
                check(list.height > 300 && list.currentIndex === 0, "Results fill centered card");
                input.keyClick(Qt.Key_Down);
                check(list.currentIndex === 1 && search.activeFocus, "Down preserves search focus");
                input.keyClick(Qt.Key_Return);
                check(root.launched.join(',') === 'beta.desktop' && !popup.opened, "Enter launches selected app and closes");
                popup.opened = true;
                input.wait(50);
                search = input.findChild(popup, 'launcherSearch');
                list = input.findChild(popup, 'applicationsList');
                search.text = 'missing-app';
                check(list.count === 0 && list.currentIndex === -1, "Empty search clears selection");
                input.keyClick(Qt.Key_Return);
                check(root.launched.length === 1 && popup.opened, "Empty results do not launch");
                search.text = 'Alpha';
                input.wait(30);
                check(list.count === 1, "Search filters apps");
                input.mouseClick(list.itemAtIndex(0), 25, 25);
                check(root.launched.join(',') === 'beta.desktop,alpha.desktop' && !popup.opened, "Click launches app and closes");
                popup.opened = true;
                input.wait(50);
                search = input.findChild(popup, 'launcherSearch');
                check(search.text === '' && search.activeFocus, "Reopen resets search and focus");
                input.keyClick(Qt.Key_Escape);
                check(!popup.opened, "Escape closes launcher");
                popup.opened = true;
                input.wait(50);
                input.mouseClick(popup, 5, 5);
                check(!popup.opened, "Outside click closes launcher");
                dropdown.section = 'launcher';
                input.wait(50);
                check(dropdown.testKeyboardFocus === WlrKeyboardFocus.Exclusive, "Launcher takes keyboard focus even from hover");
                check(dropdown.inwardRect.height === dropdown.height && dropdown.inwardRect.width === dropdown.width, "Launcher receives full-screen input");
                check(!input.findChild(dropdown, 'dropdownPopover').opened, "Launcher does not open connected menu surface");
                check(input.findChild(dropdown, 'launcherCard').visible, "Production dropdown shows centered launcher");
                dropdown.section = '';
                input.wait(30);
                check(input.findChild(dropdown, 'launcherSearch') === null, "Production close releases launcher contents");
                console.log('LAUNCHER_POPUP_OK'); Qt.quit();
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                       QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('LAUNCHER_POPUP_OK', output)
            for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop'):
                self.assertNotIn(error, output)
