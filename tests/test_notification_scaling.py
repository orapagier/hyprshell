"""Large histories stay complete across virtual scrolling, batched saves and reload."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class NotificationScalingTests(unittest.TestCase):
    def test_pending_dismissal_and_arrival_survive_reload(self):
        self.check_reload(False)

    def test_pending_changes_survive_explicit_hard_reload(self):
        self.check_reload(True)

    def check_reload(self, hard):
        with tempfile.TemporaryDirectory(prefix='hyprshell-reload-') as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    Component.onDestruction: inbox.flushHistory(true)
    PersistentProperties { id: state; reloadableId: "reload-test"; property int phase: 0 }
    NotificationInbox { id: inbox }
    Timer {
        id: driver
        interval: 20; repeat: true; running: true
        onTriggered: {
            if (!inbox.initialized) return;
            if (state.phase === 0) {
                inbox.rows = [{id:'dismissed', app:'Test', summary:'Old', body:'', actions:[]}];
                inbox.save(); inbox.flushHistory(true);
                inbox.dismiss('dismissed');
                inbox.rows = [{id:'pending-reload', app:'Test', summary:'New', body:'', actions:[]}];
                inbox.save();
                state.phase = 1;
                driver.stop();
                Quickshell.reload(false);
            } else {
                if (inbox.rows.length !== 1 || inbox.rows[0].id !== 'pending-reload') {
                    console.error('RELOAD_LOST_PENDING_CHANGES'); Qt.exit(1); return;
                }
                inbox.rows = [{id:'pending-exit', app:'Test', summary:'Exit', body:'', actions:[]}];
                inbox.save();
                console.log('RELOAD_OK'); Qt.quit();
            }
        }
    }
    Timer { interval: 4000; running: true; onTriggered: Qt.exit(2) }
}
''')
            if hard:
                entry.write_text(entry.read_text().replace('Quickshell.reload(false);',
                    'inbox.flushHistory(true); Quickshell.reload(true);').replace(
                        'if (state.phase === 0) {',
                        "if (inbox.rows.some(row => row.id === 'pending-reload')) state.phase = 1;\n            if (state.phase === 0) {"))
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(root / 'runtime'), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QS_NO_RELOAD_POPUP='1')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=7)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('RELOAD_OK', output)
            history = next((root / 'state').rglob('notifications.json'))
            self.assertEqual([r['id'] for r in json.loads(history.read_text())], ['pending-exit'], output)

    def test_large_history_virtualization_batching_and_exit(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-history-') as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: root
    Component.onDestruction: inbox.flushHistory(true)
    NotificationInbox { id: inbox }
    QtObject { id: store; property var config: ({notifications:{doNotDisturb:false}}); property bool loaded: true }
    FloatingWindow {
        visible: true; implicitWidth: 390; implicitHeight: 664
        ActivityContent { id: page; width: 354; height: 664; inbox: inbox; store: store }
    }
    TestCase { id: test; name: "HistoryScaling"; when: false }
    function cards(item) {
        let n = item.objectName.startsWith("activityNotification-") ? 1 : 0;
        for (let child of item.children || []) n += cards(child);
        return n;
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.tryVerify(() => inbox.initialized, 2000);
                test.verify(inbox.initialized);
                    test.wait(250);
                    let saved = 0;
                    inbox.historySaved.connect(() => saved++);
                    let rows = [];
                    for (let i=0; i<10000; i++) rows.push({id:String(i),app:'Synthetic',appKey:'test',
                        summary:'Notification '+i,body:'Body '+i,received:1,unread:true,active:false,actions:[]});
                    inbox.rows = rows;
                    let start = Date.now();
                    for (let i=0; i<25; i++) inbox.markRead();
                    test.compare(saved, 0);
                    test.tryVerify(() => saved === 1, 3000);
                    if (saved !== 1) throw new Error("Expected one coalesced write, got "+saved);
                    console.log('HISTORY_BATCH rows=10000 operations=25 writes='+saved+' elapsed_ms='+(Date.now()-start));
                    page.expandedGroups = ['test'];
                    test.wait(150);
                    test.compare(page.count, 10001);
                    test.verify(cards(page) > 0 && cards(page) < 40, 'Bounded cards: '+cards(page));
                    console.log('HISTORY_CARDS rows=10000 instantiated='+cards(page));
                    page.expanded = '9999';
                    page.positionViewAtEnd();
                    test.wait(150);
                    let last = test.findChild(page, 'activityNotification-9999');
                    test.verify(last !== null && last.expanded, 'Final row and details remain reachable');
                    page.focusRow(10000);
                    test.wait(100);
                    test.verify(test.findChild(last, 'notificationHeader').activeFocus, 'Offscreen keyboard navigation focuses the header');
                    page.positionViewAtBeginning();
                    test.wait(100);
                    page.positionViewAtEnd();
                    test.wait(100);
                    test.verify(test.findChild(page, 'activityNotification-9999').expanded, 'Virtualization preserves expansion');
                    inbox.clear();
                    inbox.rows = [{id:'pending-exit',app:'Test',summary:'Pending exit',body:'',actions:[]}];
                    inbox.save();
                    console.log('HISTORY_PATH '+Quickshell.statePath('notifications.json'));
                    console.log('HISTORY_SCALING_OK');
                    Qt.quit();
            } catch (error) { console.error(error, error.stack); Qt.exit(1); }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: Qt.exit(2) }
}
''')
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software', QS_NO_RELOAD_POPUP='1')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HISTORY_SCALING_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)
            history = next((root / 'state').rglob('notifications.json'))
            self.assertEqual([r['id'] for r in json.loads(history.read_text())], ['pending-exit'], output)
            for line in output.splitlines():
                if 'HISTORY_BATCH' in line or 'HISTORY_CARDS' in line:
                    print(line.strip())


if __name__ == '__main__':
    unittest.main()
