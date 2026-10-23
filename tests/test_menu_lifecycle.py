"""Closed menus release their UI without interrupting motion, work or keyboard input."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class MenuLifecycleTests(unittest.TestCase):
    def test_close_reopen_and_deferred_work(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: root
    property int completed: 0
    property int deferred: 0
    property bool chainWork: false
    QtObject {
        id: apps
        property var entries: [{id:"alpha.desktop",name:"Alpha",genericName:"Test app"}]
        function launch(entry) { return true; }
        function iconSource(icon) { return ""; }
    }
    FloatingWindow {
        visible: true; implicitWidth: 1000; implicitHeight: 800
        MenuPopover {
            id: menu
            anchors.fill: parent
            persistentSelected: true
            persistentPage: Component {
                Item {
                    id: worker
                    implicitHeight: 100
                    property bool busy: false
                    onBusyChanged: if (!busy) {
                        root.completed++;
                        Qt.callLater(() => {
                            root.deferred++;
                            if (root.chainWork) worker.busy = true;
                        });
                    }
                }
            }
        }
        MenuPopover {
            id: launcher
            anchors.fill: parent
            persistentSelected: true
            instant: true
            persistentPage: Component {
                LauncherMenu { active: launcher.opened; applicationService: apps }
            }
        }
    }
    TestCase { id: input; when: false }
    function check(ok, message) { if (!ok) throw new Error(message); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(menu.pageItem === null && launcher.pageItem === null, "Closed pages are absent at startup");
                menu.opened = true;
                input.wait(500);
                check(menu.pageItem !== null, "Opening creates contents");
                menu.opened = false;
                check(menu.pageItem !== null, "Closing animation retains contents");
                input.tryVerify(() => !menu.rendering && menu.pageItem === null, 3000);
                check(menu.pageItem === null, "Settled close releases contents");
                menu.instant = true;
                menu.opened = true;
                menu.pageItem.busy = true;
                menu.opened = false;
                input.wait(50);
                check(menu.pageItem !== null, "Closed page retains pending work");
                root.chainWork = true;
                menu.pageItem.busy = false;
                input.wait(50);
                check(root.completed === 1 && root.deferred === 1, "Exit callbacks finish before destruction");
                check(menu.pageItem !== null && menu.pageItem.busy, "Deferred follow-up job survives close");
                root.chainWork = false;
                menu.pageItem.busy = false;
                input.tryVerify(() => menu.pageItem === null, 1000);
                check(root.completed === 2 && root.deferred === 2 && menu.pageItem === null, "Finished work releases contents");
                for (let i = 0; i < 3; ++i) {
                    launcher.opened = true;
                    input.wait(50);
                    let search = input.findChild(launcher.pageItem, 'launcherSearch');
                    let list = input.findChild(launcher.pageItem, 'applicationsList');
                    check(search.activeFocus && search.text === '', "Fresh launcher focuses empty search");
                    check(list.currentIndex === 0, "Fresh launcher selects the first app");
                    input.keyClick(Qt.Key_A);
                    check(search.text === 'a', "Typing works after recreation");
                    launcher.opened = false;
                    input.tryVerify(() => launcher.pageItem === null, 1000);
                    check(launcher.pageItem === null, "Closed launcher releases contents");
                }
                console.log('MENU_LIFECYCLE_OK'); Qt.quit();
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
            self.assertIn('MENU_LIFECYCLE_OK', output)
            for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop'):
                self.assertNotIn(error, output)
