import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

SettingsCard {
    id: page
    property bool ready: true
    property var checkpoints: []
    property var preview: null
    property string revision: ""
    property string message: ""
    property bool success: true
    property bool loaded: false
    readonly property bool busy: worker.running
    signal restored(var settings)
    title: "Complete personal configuration"
    subtitle: "Checkpoints include Settings, displays, shortcuts, app preferences, GTK/Qt environment, startup entries, file associations and manually edited desktop Lua. Installed shell code and personal documents are excluded."
    onVisibleChanged: { if (visible && !busy) request("status"); if (!visible) preview = null; }
    Component.onCompleted: if (visible) request("status")
    function request(operation, ident) {
        if (busy || !ready) return;
        let payload = {operation: operation, id: ident || "", expected: revision, token: preview ? preview.token : ""};
        if (operation !== "restore") preview = null;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/configuration.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector { onStreamFinished: {
            try {
                let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                if (result.ok) { page.loaded = true; page.checkpoints = result.checkpoints; page.revision = result.revision; page.preview = result.preview || null; if (result.restored) page.restored(result.restored); }
                else page.preview = null;
            } catch (e) { page.success = false; page.message = "Could not read configuration recovery. Refresh and retry."; }
        } }
    }
    SettingsLabel { visible: !page.ready; text: "Wait for Settings to finish saving."; color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Flow {
        Layout.fillWidth: true; spacing: 8
        SettingsButton { objectName: "createConfigurationCheckpoint"; text: "Create complete checkpoint"; enabled: page.loaded && page.ready && !page.busy; onClicked: page.request("checkpoint") }
        SettingsButton { text: "Refresh checkpoints"; enabled: page.ready && !page.busy; onClicked: page.request("status") }
    }
    SettingsComboBox { id: picker; objectName: "configurationCheckpointPicker"; Layout.fillWidth: true; model: page.checkpoints.map(row => row.label); enabled: page.ready && !page.busy && page.checkpoints.length > 0 }
    SettingsButton { objectName: "previewConfigurationRestore"; text: "Preview complete restore…"; enabled: page.ready && !page.busy && picker.currentIndex >= 0 && page.checkpoints.length > 0; onClicked: page.request("preview", page.checkpoints[picker.currentIndex].id) }
    SettingsLabel { visible: page.preview !== null; text: page.preview ? page.preview.changes.length ? "Files to restore:\n" + page.preview.changes.join("\n") + "\nCurrent files receive an undo backup. Saved manual Lua and startup commands load on your next login. Log out and back in after restoring." : "This checkpoint matches the current configuration." : ""; textFormat: Text.PlainText; color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
    RowLayout {
        visible: page.preview !== null
        SettingsButton { objectName: "confirmConfigurationRestore"; text: "Restore complete configuration"; highlighted: true; enabled: page.ready && !page.busy && page.preview !== null && page.preview.changes.length > 0; onClicked: page.request("restore") }
        SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.preview = null }
    }
    SettingsLabel { text: page.message; visible: !!text; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
