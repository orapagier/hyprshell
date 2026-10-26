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
    property string selectedId: ""
    property string backupDirectory: ""
    property int skippedBackups: 0
    readonly property var selectedBackup: checkpoints.find(row => row.id === selectedId) || null
    readonly property bool busy: worker.running
    signal restored(var settings)
    title: "Hyprshell setup backup & restore"
    subtitle: "Back up Settings, displays, shortcuts, app preferences, GTK/Qt environment, startup entries, file associations and manually edited desktop Lua. Select a dated backup to preview and restore. Installed shell code, system packages and personal documents are excluded."
    onVisibleChanged: { if (visible && !busy) request("status"); if (!visible) preview = null; }
    Component.onCompleted: if (visible) request("status")
    onReadyChanged: if (ready && visible && !loaded && !busy) request("status")
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
                if (result.ok) {
                    let wanted = result.createdBackup || page.selectedId;
                    page.loaded = true; page.checkpoints = result.checkpoints; page.revision = result.revision;
                    page.backupDirectory = result.backupDirectory || ""; page.skippedBackups = result.skippedBackups || 0;
                    let index = page.checkpoints.findIndex(row => row.id === wanted);
                    picker.currentIndex = index >= 0 ? index : page.checkpoints.length ? 0 : -1;
                    page.selectedId = picker.currentIndex >= 0 ? page.checkpoints[picker.currentIndex].id : "";
                    page.preview = result.preview || null; if (result.restored) page.restored(result.restored);
                }
                else page.preview = null;
            } catch (e) { page.success = false; page.message = "Could not read configuration recovery. Refresh and retry."; }
        } }
    }
    SettingsLabel { visible: !page.ready; text: "Wait for Settings to finish saving."; color: Style.SettingsTheme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Flow {
        Layout.fillWidth: true; spacing: 8
        SettingsButton { objectName: "createConfigurationCheckpoint"; text: page.busy ? "Working…" : "Back up Hyprshell now"; enabled: page.loaded && page.ready && !page.busy; onClicked: page.request("checkpoint") }
        SettingsButton { objectName: "refreshSetupBackups"; text: "Refresh backups"; enabled: page.ready && !page.busy; onClicked: page.request("status") }
        SettingsButton { text: "Open backup folder"; enabled: !page.busy && !!page.backupDirectory && page.checkpoints.some(row => row.kind !== "legacy"); onClicked: Qt.openUrlExternally("file://" + page.backupDirectory.split("/").map(encodeURIComponent).join("/")) }
    }
    SettingsLabel { visible: page.loaded && page.checkpoints.length === 0; text: "No setup backups yet. Back up Hyprshell now to create your first dated restore point."; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: "Choose a backup to restore · newest first"; color: Style.SettingsTheme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsComboBox {
        id: picker; objectName: "configurationCheckpointPicker"; Layout.fillWidth: true
        model: page.checkpoints.map(row => row.label); enabled: page.ready && !page.busy && page.checkpoints.length > 0
        onActivated: { page.selectedId = page.checkpoints[currentIndex].id; page.preview = null; }
        Accessible.name: "Hyprshell backup date and time"
    }
    SettingsLabel { objectName: "selectedSetupBackup"; visible: page.selectedBackup !== null; text: page.selectedBackup ? page.selectedBackup.label + "\n" + (page.selectedBackup.fileCount !== null ? page.selectedBackup.fileCount + " configuration files · " : "") + (page.selectedBackup.bytes / 1024).toFixed(1) + " KiB" : ""; textFormat: Text.PlainText; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: "New manual setup backups and before-restore backups are kept separately from cleanup history. Copy the backup folder to another drive for protection against disk failure or reinstalling the OS. Legacy checkpoints remain subject to their existing cleanup rules."; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { visible: page.skippedBackups > 0; text: page.skippedBackups + " incomplete or invalid backup entries were skipped. Check the backup folder before relying on them."; color: Style.SettingsTheme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsButton { objectName: "previewConfigurationRestore"; text: "Preview selected backup…"; enabled: page.ready && !page.busy && !!page.selectedId; onClicked: page.request("preview", page.selectedId) }
    SettingsLabel { visible: page.preview !== null; text: page.preview ? "Selected backup: " + page.preview.label + "\n" + (page.preview.changes.length ? "Files to restore:\n" + page.preview.changes.join("\n") + "\nYour current setup receives a dated before-restore backup. Saved manual Lua and startup commands load on your next login. Log out and back in after restoring." : "This backup matches the current configuration.") : ""; textFormat: Text.PlainText; color: Style.SettingsTheme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
    RowLayout {
        visible: page.preview !== null
        SettingsButton { objectName: "confirmConfigurationRestore"; text: "Restore this backup"; highlighted: true; enabled: page.ready && !page.busy && page.preview !== null && page.preview.changes.length > 0; onClicked: page.request("restore") }
        SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.preview = null }
    }
    SettingsLabel { text: page.message; visible: !!text; color: page.success ? Style.SettingsTheme.success : Style.SettingsTheme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
