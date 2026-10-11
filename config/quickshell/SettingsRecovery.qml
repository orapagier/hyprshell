import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property bool ready: true
    property bool loaded: false
    property bool success: true
    property string message: ""
    property string revision: ""
    property var backups: []
    property var preview: null
    property var personal: ({folder: "", confirmed: "", available: false})
    property var upgrade: ({status: "none", message: ""})
    property var updates: null
    property string action: ""
    readonly property bool busy: worker.running
    readonly property bool upgrading: upgrade.status === "launching" || upgrade.status === "running"
    signal restored(var settings)
    spacing: 16
    Component.onCompleted: if (visible) request({operation: "status"})
    onVisibleChanged: {
        if (visible && !busy) request({operation: "status"});
        if (!visible) preview = null;
    }

    function request(payload) {
        if (busy || (!ready && ["checkpoint", "preview", "restore"].indexOf(payload.operation) >= 0)) return;
        action = payload.operation;
        if (action !== "restore") preview = null;
        payload.expected = revision;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/recovery.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    Process {
        id: worker
        onExited: (code, status) => {
            if (code !== 0 && page.success) { page.success = false; page.message = "Recovery helper failed. Refresh and try again."; }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    if (result.message || !result.ok || page.action !== "status") page.message = result.message || "";
                    if (result.ok) {
                        page.backups = result.backups;
                        page.revision = result.revision;
                        page.personal = result.personal;
                        page.upgrade = result.upgrade;
                        page.loaded = true;
                        if (result.updates) page.updates = result.updates;
                        if (result.preview) page.preview = result.preview;
                        if (result.restored) { page.preview = null; page.restored(result.restored); }
                    } else if (page.action === "restore") page.preview = null;
                } catch (e) { page.success = false; page.message = "Could not read recovery status. Refresh and try again."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = "Recovery helper failed. Refresh and try again."; } }
    }
    Timer {
        interval: 3000; repeat: true; running: page.visible && page.upgrading && page.preview === null
        onTriggered: if (!page.busy) page.request({operation: "status"})
    }
    Label { visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsButton { objectName: "refreshRecovery"; text: "Refresh"; enabled: !page.busy; onClicked: page.request({operation: "status"}) }
    SettingsCard {
        title: "System updates"
        subtitle: "Read Arch news before upgrading, save your work, and check your backup. The upgrade window asks for your password and lets you review all package changes."
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            SettingsButton { objectName: "checkSystemUpdates"; text: page.busy && page.action === "check-updates" ? "Checking…" : "Check for updates"; enabled: !page.busy && !page.upgrading; onClicked: page.request({operation: "check-updates"}) }
            SettingsButton { text: "Arch news"; onClicked: Qt.openUrlExternally("https://archlinux.org/news/") }
        }
        Label { text: page.updates ? page.updates.packages.length + " repository updates · checked " + page.updates.checked : "Update availability has not been checked."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
        ScrollView {
            visible: page.updates !== null && page.updates.packages.length > 0
            Layout.fillWidth: true; Layout.preferredHeight: 130; clip: true
            TextArea { text: page.updates ? page.updates.packages.join("\n") : ""; readOnly: true; selectByMouse: true; wrapMode: Text.Wrap; color: Style.Theme.text; font.pixelSize: Style.Theme.captionSize }
        }
        SettingsButton { objectName: "startSystemUpgrade"; text: page.upgrading ? "Upgrade window open" : "Open full system upgrade…"; enabled: page.loaded && !page.busy && !page.upgrading; onClicked: page.request({operation: "upgrade"}) }
        Label { text: page.upgrade.message; color: ["failed", "unknown"].indexOf(page.upgrade.status) >= 0 ? Style.Theme.danger : Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { text: "AUR and other foreign packages need separate review after the full upgrade. The terminal stays open when you close Settings."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { text: "Upgrade troubleshooting"; onClicked: Qt.openUrlExternally("https://wiki.archlinux.org/title/System_maintenance#Upgrading_the_system") }
    }
    SettingsCard {
        title: "Desktop settings recovery"
        subtitle: "Restore bar layout, compositor appearance, input, power, locking, and notification preferences. Displays, app defaults, application theme, keybindings, and manually edited Lua files are outside this restore."
        Layout.fillWidth: true
        Label { visible: !page.ready; text: "Wait for Settings to finish saving before creating or restoring a checkpoint."; color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { objectName: "createSettingsCheckpoint"; text: "Save current settings checkpoint"; enabled: page.loaded && page.ready && !page.busy; onClicked: page.request({operation: "checkpoint"}) }
        SettingsComboBox { id: backupPicker; objectName: "settingsBackupPicker"; Layout.fillWidth: true; model: page.backups.map(entry => entry.label); enabled: !page.busy && page.ready && page.backups.length > 0 }
        Label { visible: page.loaded && page.backups.length === 0; text: "No saved desktop settings backups found. Create a checkpoint to start."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { objectName: "previewSettingsRestore"; text: "Preview restore…"; enabled: page.loaded && page.ready && !page.busy && backupPicker.currentIndex >= 0 && page.backups.length > 0; onClicked: page.request({operation: "preview", id: page.backups[backupPicker.currentIndex].id}) }
        Label { objectName: "settingsRestorePreview"; visible: page.preview !== null; text: page.preview ? page.preview.changes.length ? "Will restore: " + page.preview.changes.join(", ") + ". Current settings are backed up before applying." : "This backup matches your current settings." : ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Style.Theme.warning }
        RowLayout {
            visible: page.preview !== null
            SettingsButton { objectName: "confirmSettingsRestore"; text: "Restore these settings"; highlighted: true; enabled: page.ready && !page.busy && page.preview !== null && page.preview.changes.length > 0; onClicked: page.request({operation: "restore", token: page.preview.token}) }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.preview = null }
        }
        Label { text: "Recovery backups stay on this laptop and may be removed by your System cleanup policy. GitHub sync preserves the current saved configuration."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
    SettingsCard {
        title: "Personal-file backup status"
        subtitle: "GitHub configuration sync does not back up Documents, Pictures, or other personal files. After using your backup app, check the backup and record the folder here."
        Layout.fillWidth: true
        Label { objectName: "personalBackupStatus"; text: page.personal.confirmed ? "Last backup check you confirmed: " + Qt.formatDateTime(new Date(page.personal.confirmed), "yyyy-MM-dd HH:mm") + "\n" + page.personal.folder + "\n" + (page.personal.available ? "Folder is currently readable." : "Folder is currently unavailable. Connect the backup drive and check again.") : "No personal backup check has been recorded."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
        TextField { id: backupFolder; objectName: "personalBackupFolder"; Layout.fillWidth: true; placeholderText: "Absolute backup folder path"; text: page.personal.folder; color: Style.Theme.text; selectByMouse: true; enabled: !page.busy }
        SettingsButton { objectName: "confirmPersonalBackup"; text: "I checked my backup today"; enabled: page.loaded && !page.busy && backupFolder.text.trim().length > 0; onClicked: page.request({operation: "confirm-backup", folder: backupFolder.text}) }
        Label { text: "This is your confirmation, not an automatic backup or verification of file contents. The folder and date stay local and are excluded from GitHub sync."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
}
