import QtQuick
import Quickshell.Io

Item {
    id: controller
    property bool hidden: false
    property string error: ''
    readonly property bool busy: worker.running
    signal actionFinished(bool success)
    Component.onCompleted: run('status')
    function run(action, output) {
        if (busy) return false;
        error = '';
        if (action === 'toggle' && hidden) action = 'restore';
        worker.command = ['python3', decodeURIComponent(Qt.resolvedUrl('settings/show_desktop.py').toString().replace(/^file:\/\//, '')), action];
        if (output) worker.command = worker.command.concat(['--output', output]);
        worker.running = true;
        return true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (result.ok) controller.hidden = result.hidden;
                    else { controller.hidden = true; controller.error = result.message || 'Desktop windows could not be restored.'; }
                    controller.actionFinished(!!result.ok);
                } catch (error) {
                    controller.hidden = true;
                    controller.error = 'The desktop action did not return a result. Use Restore again.';
                    controller.actionFinished(false);
                }
            }
        }
    }
}
