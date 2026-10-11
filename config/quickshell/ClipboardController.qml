import QtQuick
import Quickshell.Io

Item {
    id: controller
    required property var store
    property string error: ""
    property string fingerprint: ""
    property bool restarting: false
    property bool stopping: false
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("settings/clipboard.py").toString().replace(/^file:\/\//, ""))
    function sync() {
        if (!store.loaded) return;
        let next = JSON.stringify(store.config.clipboard);
        if (next === fingerprint) return;
        fingerprint = next; error = ""; restarting = true;
        if (watcher.running && !stopping) { stopping = true; watcher.running = false; }
        else if (!stopping) restart.restart();
    }
    Component.onCompleted: sync()
    Connections { target: controller.store; function onConfigChanged() { controller.sync(); } function onLoadedChanged() { controller.sync(); } }
    Timer { id: restart; interval: 100; onTriggered: { controller.restarting = false; if (controller.store.config.clipboard.enabled) watcher.running = true; } }
    Process {
        id: watcher
        command: ["python3", controller.helper, "--watch"]
        stderr: StdioCollector { onStreamFinished: if (text && !controller.restarting) controller.error = "Clipboard history stopped. Install tools or check desktop access; toggle history to retry." }
        onExited: (code, status) => {
            controller.stopping = false;
            if (controller.restarting) restart.restart();
            else if (controller.store.config.clipboard.enabled) controller.error = "Clipboard history stopped. Toggle history to retry.";
        }
    }
}
