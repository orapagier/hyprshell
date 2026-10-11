pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "SettingsModel.js" as Model
import "style" as Style

SettingsCard {
    id: page
    property var draft: ({version: 1, destination: "", sources: [], schedule: "off", device: null, inode: null})
    property var initial: null
    property var folders: []
    property var status: ({phase: "none", message: ""})
    property string message: ""
    property bool success: true
    readonly property bool busy: worker.running
    readonly property bool pending: initial !== null && JSON.stringify(draft) !== JSON.stringify(initial)
    readonly property bool dirty: pending
    title: "Personal-file backups"
    subtitle: "Copy selected personal folders to a connected local drive or folder. Scheduling is off until enabled. Snapshots and paths stay local and are excluded from GitHub sync."
    Component.onCompleted: if (visible) request("status")
    onVisibleChanged: if (visible && !busy && !dirty) request("status")
    function edit(key, value) { let next = Model.copy(draft); next[key] = value; draft = next; }
    function toggleSource(path, enabled) { edit("sources", enabled ? draft.sources.concat([path]) : draft.sources.filter(value => value !== path)); }
    function request(operation) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/personal_backup.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify({operation: operation, settings: draft, expected: initial})]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector { onStreamFinished: {
            try {
                let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                if (result.ok) {
                    if (result.settings) { page.initial = result.settings; page.draft = Model.copy(result.settings); }
                    if (result.status) page.status = result.status;
                    if (result.folders) page.folders = result.folders;
                }
            } catch (e) { page.success = false; page.message = "Could not read personal backup controls. Refresh to retry."; }
        } }
    }
    SettingsLabel { text: "Backup destination"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
    SettingsTextField { objectName: "automaticBackupDestination"; Layout.fillWidth: true; placeholderText: "Existing absolute folder on your backup drive"; text: page.draft.destination; color: Style.Theme.text; selectByMouse: true; onTextEdited: page.edit("destination", text) }
    SettingsLabel { text: "Select personal folders"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
    Repeater {
        model: page.folders
        delegate: SettingsSwitch {
            required property var modelData
            text: modelData.name; checked: page.draft.sources.indexOf(modelData.path) >= 0; Layout.fillWidth: true
            onToggled: page.toggleSource(modelData.path, checked)
        }
    }
    SettingsTextField { id: customFolder; Layout.fillWidth: true; placeholderText: "Another personal folder inside your home (absolute path)"; color: Style.Theme.text; selectByMouse: true }
    SettingsButton { text: "Add source folder"; enabled: customFolder.text.trim().length > 0 && page.draft.sources.indexOf(customFolder.text.trim()) < 0; onClicked: { page.toggleSource(customFolder.text.trim(), true); customFolder.text = ""; } }
    Repeater {
        model: page.draft.sources
        delegate: RowLayout {
            id: sourceRow
            required property string modelData
            Layout.fillWidth: true
            SettingsLabel { text: sourceRow.modelData; textFormat: Text.PlainText; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            SettingsButton { text: "Remove"; onClicked: page.toggleSource(sourceRow.modelData, false) }
        }
    }
    SettingsLabel { text: "Automatic schedule"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
    SettingsComboBox { Layout.fillWidth: true; model: ["Off · manual backups", "Daily", "Weekly"]; currentIndex: ["off", "daily", "weekly"].indexOf(page.draft.schedule); onActivated: index => page.edit("schedule", ["off", "daily", "weekly"][index]) }
    Flow {
        Layout.fillWidth: true; spacing: 8
        SettingsButton { objectName: "saveAutomaticBackup"; text: "Save backup preferences"; highlighted: page.pending; enabled: page.initial !== null && !page.busy && page.status.phase !== "running"; onClicked: page.request("save") }
        SettingsButton { text: page.pending ? "Discard edits & refresh" : "Refresh status"; enabled: !page.busy; onClicked: page.request("status") }
        SettingsButton { objectName: "runPersonalBackup"; text: "Back up now"; enabled: !page.busy && !page.pending && page.initial !== null && !!page.initial.destination && page.initial.sources.length > 0 && page.status.phase !== "running"; onClicked: page.request("run") }
        SettingsButton { text: "Verify latest snapshot"; enabled: !page.busy && !page.pending && page.initial !== null && !!page.initial.destination && page.status.phase !== "running"; onClicked: page.request("verify") }
        SettingsButton { text: "Open snapshots / recover files"; enabled: !page.busy && !page.pending && page.initial !== null && !!page.initial.destination; onClicked: page.request("open") }
    }
    SettingsLabel { text: page.status.message + (page.status.time ? "\n" + Qt.formatDateTime(new Date(page.status.time), "yyyy-MM-dd HH:mm") : ""); textFormat: Text.PlainText; color: ["failed", "interrupted"].indexOf(page.status.phase) >= 0 ? Style.Theme.danger : Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: "Symbolic links and special files are skipped. Snapshots reuse verified unchanged copies and keep older versions. Snapshots are never deleted automatically; watch free space. Scheduled backups require the selected destination to remain connected and your user session to be running."; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: "Recover files from the snapshot folder into a separate folder first. Check them before replacing originals. A backup on the same drive cannot protect against that drive failing."; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: page.message; visible: !!text; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
