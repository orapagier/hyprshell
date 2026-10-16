import QtQuick
import Quickshell.Io

Item {
    id: utilities
    property bool watching: false
    property bool full: false
    property bool available: false
    property string error: ''
    readonly property bool busy: worker.running
    property string pending: ''
    function run(action) {
        if (busy) return false;
        pending = action; error = '';
        worker.command = ['python3', decodeURIComponent(Qt.resolvedUrl('settings/dock_utilities.py').toString().replace(/^file:\/\//, '')), action];
        worker.running = true;
        return true;
    }
    function refresh() { if (watching && !busy) run('status'); }
    onWatchingChanged: if (watching) refresh()
    Timer { interval: 15000; repeat: true; running: utilities.watching; onTriggered: utilities.refresh() }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (utilities.pending === 'status') utilities.available = result.ok;
                    if (result.ok && result.full !== undefined) utilities.full = result.full;
                    if (!result.ok) utilities.error = result.message;
                    if (utilities.pending === 'empty-confirmed' && result.ok) utilities.full = false;
                } catch (error) { utilities.error = 'The file manager action failed.'; }
            }
        }
    }
}
