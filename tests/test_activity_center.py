"""Exercise production right-corner content with isolated notifications and players."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class ActivityCenterTests(unittest.TestCase):
    def test_right_corner_notifications_and_direct_player_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'shell'
            payload.mkdir()
            for source in (ROOT / 'config/quickshell').iterdir():
                if source.name not in ('Dashboard.qml', 'settings'):
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            source = (ROOT / 'config/quickshell/Dashboard.qml').read_text().replace('PanelWindow {', 'FloatingWindow {')
            source = '\n'.join(line for line in source.splitlines() if not any(
                token in line for token in ('anchors { top:', 'anchors { left:', 'margins {', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.')))
            (payload / 'Dashboard.qml').write_text(source)
            # A fake writer verifies arguments without changing desktop preferences.
            (payload / 'settings').mkdir()
            (payload / 'settings/backend.py').write_text('''import json, sys
args = sys.argv
before = json.loads(args[args.index('--expected-json') + 1])
after = json.loads(args[args.index('--save-json') + 1])
assert before['notifications']['doNotDisturb'] is False
assert after['notifications']['doNotDisturb'] is True
assert after['bar'] == before['bar']
print(json.dumps({'ok': True}))
''')
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: test
    function check(value, message) { if (!value) throw new Error(message); }
    function find(root, name) { return input.findChild(root, name); }
    function click(item) { input.mouseClick(item, item.width / 2, item.height / 2); }
    QtObject {
        id: mockInbox
        property var rows: []
        property int unread: rows.filter(r => r.unread).length
        property int actionCalls: 0
        function markRead() { rows = rows.map(r => Object.assign({}, r, {unread:false})); }
        function dismiss(id) { rows = rows.filter(r => r.id !== id); }
        function clear() { rows = []; }
        function invoke(id, action) { actionCalls++; }
    }
    QtObject {
        id: mockStore
        property var config: ({notifications:{doNotDisturb:false},bar:{position:'top'}})
        property bool loaded: true
        property int reloads: 0
        function reload() { reloads++; }
    }
    component Player: QtObject {
        property bool isPlaying: false
        property bool canPlay: true
        property bool canPause: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        property string trackTitle: "A track"
        property string identity: "Test player"
        property string trackArtist: "Artist"
        property string trackArtUrl: ""
        property int nextCalls: 0
        property int previousCalls: 0
        function togglePlaying() { isPlaying = !isPlaying; }
        function next() { nextCalls++; trackTitle = "Next track"; }
        function previous() { previousCalls++; }
    }
    Player { id: first }
    Player { id: second; isPlaying: true; trackTitle: "Playing track" }
    TestCase { id: input; name: "ActivityInput"; when: false }
    Dashboard {
        id: drawer
        services: ({})
        rightCorner: true
        width: 1100; height: 850
        contentPage: Component {
            ActivityContent {
                inbox: mockInbox; store: mockStore
                active: drawer.opened
                screenWidth: drawer.width; screenHeight: drawer.height
                onDismissRequested: drawer.close()
            }
        }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            try {
                let page = test.find(drawer.contentItem, 'activityContent');
                test.check(page !== null, "Activity page loads");
                let popover = test.find(drawer.contentItem, 'dashboardPopover');
                let media = test.find(page, 'activityMedia');
                media.players = [first, second];
                test.check(media.player === second, "Playing player takes precedence over paused player");
                drawer.enterCorner(null);
                input.wait(350);
                test.check(drawer.opened, "Right corner opens immediately");
                test.check(popover.attachedRight && popover.attachedCorner, "Drawer uses right corner surface");
                test.check(popover.bodyRight === drawer.width && popover.bodyBottom === drawer.height, "Drawer joins bottom-right screen corner");
                test.check(drawer.revealRect.x + drawer.revealRect.width === drawer.width, "Reveal strip touches right edge");
                test.check(popover.bodyWidth === 390, "Activity center stays narrow");
                test.check(popover.containsPointer(Qt.point(popover.bodyX - popover.footRadius / 2, drawer.height - 2)), "Mirrored foot retains hover");
                test.check(!popover.containsPointer(Qt.point(0,0)), "Opposite corner is outside drawer");
                input.mouseMove(drawer.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                test.find(drawer.contentItem, 'dashboardMenuState').leave('dashboard');
                input.wait(500);
                let button = test.find(media,'activityPlayPause');
                input.grabImage(drawer.contentItem).save('/tmp/activity-test.png');
                input.mouseClick(button, button.width / 2, button.height / 2);
                test.check(!second.isPlaying && !first.isPlaying, "Pause targets current player only");
                test.check(media.player === second, "Paused target is retained");
                test.click(test.find(media,'activityPlayPause'));
                test.check(second.isPlaying, "Play resumes same player");
                test.click(test.find(media,'activityNext'));
                test.click(test.find(media,'activityPrevious'));
                test.check(second.nextCalls === 1 && second.previousCalls === 1 && first.nextCalls === 0, "Track controls target selected player");
                test.check(test.find(media,'activityTrackTitle').text === 'Next track', "Metadata follows player");
                second.isPlaying = false; first.isPlaying = true;
                test.check(media.player === first, "New playing app becomes target");
                first.canGoNext = false; first.canPause = false;
                test.check(!test.find(media,'activityNext').enabled && !test.find(media,'activityPlayPause').enabled, "Unsupported actions are disabled");
                media.players = [second];
                test.check(media.player === second, "Removed player is discarded");
                media.players = [];
                test.check(!media.visible, "Card hides when no player exists");
                mockInbox.rows = [
                    {id:'1',app:'Mail',appKey:'mail',summary:'One',body:'Body',received:Date.now(),unread:true,active:true,actions:[]},
                    {id:'2',app:'Chat',appKey:'chat',summary:'Two',body:'Body',received:Date.now(),unread:true,active:true,actions:[]},
                    {id:'3',app:'Mail',appKey:'mail',summary:'Three',body:'Body',received:Date.now(),unread:true,active:true,actions:[]}
                ];
                test.check(page.groups.length === 2 && page.groups[0].rows.length === 2, "History grouped by application");
                input.wait(30);
                test.check(mockInbox.unread === 0, 'Read state after event loop: ' + drawer.opened);
                test.check(mockInbox.unread === 0, "Visible inbox marks notifications read");
                drawer.close();
                mockInbox.rows = mockInbox.rows.concat([{id:'4',app:'Mail',summary:'Unread',body:'',unread:true,actions:[]}]);
                test.check(mockInbox.unread === 1, "Closed drawer preserves unread state");
                drawer.reveal(null);
                input.wait(30);
                test.check(mockInbox.unread === 0, 'Read state after event loop: ' + drawer.opened);
                test.check(mockInbox.unread === 0, "Reopening marks history read");
                input.wait(350);
                test.click(test.find(page,'activityClear'));
                test.check(mockInbox.rows.length === 0 && test.find(page,'activityEmpty').visible, "Clear all shows empty state");
                let quiet = test.find(page,'activityDnd');
                test.click(quiet);
                input.wait(500);
                test.check(mockStore.reloads === 1, 'DND writer completes: ' + page.error);
                test.check(page.error === '', "Do Not Disturb saves through isolated writer");
                page.dismissRequested();
                test.check(!drawer.opened, "Escape/dismiss closes drawer");
                drawer.reveal(null);
                input.mouseMove(drawer.contentItem, popover.bodyX + 50, popover.bodyY + 50);
                input.mouseMove(drawer.contentItem, 1, 1);
                input.wait(1800);
                test.check(!drawer.opened, "Leaving the card dismisses it");
                console.log('ACTIVITY_NATIVE_OK'); Qt.quit();
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('ACTIVITY_NATIVE_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)


if __name__ == '__main__':
    unittest.main()
