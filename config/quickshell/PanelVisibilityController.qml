pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "SettingsModel.js" as Settings

Item {
    id: controller
    required property var store
    property var editor: null
    property var pending: []
    property var previews: ({})
    property var activeRequest: null
    property int serial: 0
    readonly property bool busy: activeRequest !== null || pending.length > 0
    readonly property var config: {
        let result = Settings.copy(store.panelConfig);
        for (let workspace of Object.keys(previews))
            result.bar = Settings.withWorkspaceVisibility(result.bar, Number(workspace), previews[workspace].visible);
        return result;
    }

    function toggle(workspace) {
        if (editor) {
            editor.toggleWorkspacePanel('hyprpane', workspace);
            return;
        }
        let request = {workspace: workspace, visible: !Settings.barVisible(config.bar, workspace), serial: ++serial};
        let next = Object.assign({}, previews);
        next[String(workspace)] = request;
        previews = next;
        pending = pending.concat([request]);
        queue.restart();
    }

    function complete(result) {
        let request = activeRequest;
        if (!request) return;
        if (result.ok) store.config = result.settings;
        else console.warn("Panel visibility was not saved: " + result.message);
        // An older save must never undo a more recent key press.
        let next = Object.assign({}, previews);
        if (next[String(request.workspace)]?.serial === request.serial)
            delete next[String(request.workspace)];
        previews = next;
        activeRequest = null;
        store.reload();
        queue.restart();
    }

    Process {
        id: writer
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            let result;
            try {
                result = JSON.parse(output.text);
                if (code !== 0 || !result.settings) result.ok = false;
            } catch (error) {
                result = {ok: false, message: "The settings writer did not complete (exit " + code + ")."};
            }
            controller.complete(result);
        }
    }
    Timer {
        id: queue
        interval: 0
        onTriggered: {
            if (writer.running || controller.activeRequest || controller.pending.length === 0) return;
            let request = controller.pending[0];
            controller.pending = controller.pending.slice(1);
            controller.activeRequest = request;
            writer.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/backend.py").toString().replace(/^file:\/\//, "")),
                "--set-bar-visibility", String(request.workspace), request.visible ? "show" : "hide"];
            writer.running = true;
        }
    }
}
