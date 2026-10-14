import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import Quickshell

ColumnLayout {
    id: page
    property var settings: ({schedule: "off", days: 30, keep: 5, thumbnails: true, temporary: true, backups: true})
    property string message: ""
    property string paccache: "Checking…"
    property string timerStatus: "Checking…"
    property var preview: null
    property string action: ""
    property bool loaded: false
    property var initial: ({})
    readonly property bool dirty: loaded && JSON.stringify(settings) !== JSON.stringify(initial)
    property bool resetReady: true
    signal restored(var settings)
    readonly property bool busy: worker.running || manualCleanup.busy || systemCleanup.busy || factoryReset.busy
    spacing: 20
    onVisibleChanged: if (visible && !dirty) request("status", "")
    Component.onCompleted: if (visible) request("status", "")
    function request(operation, value) {
        if (worker.running || (operation !== "status" && busy)) return;
        action = operation;
        if (operation !== "clean") preview = null;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/cleanup.py").toString().replace(/^file:\/\//, "")), "--" + operation];
        if (value !== "") worker.command = worker.command.concat([value]);
        worker.running = true;
    }
    function edit(key, value) {
        let next = Object.assign({}, settings);
        next[key] = value;
        settings = next;
        preview = null;
        message = "Save cleanup settings to apply these choices.";
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.message = result.message || "";
                    if (result.ok && result.settings) {
                        page.settings = result.settings;
                        page.initial = Object.assign({}, result.settings);
                        page.paccache = result.paccache;
                        page.timerStatus = result.timer;
                        page.loaded = true;
                    }
                    if (page.action === "preview" && result.ok) page.preview = result;
                    if (page.action === "clean") page.preview = null;
                } catch (e) { page.message = "Could not read cleanup results."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) page.message = text }
    }
    SettingsCleanupTargets { id: manualCleanup; objectName: "manualCleanupTargets"; Layout.fillWidth: true; enabled: !worker.running && !systemCleanup.busy && !factoryReset.busy }
    SettingsCleanupTargets { id: systemCleanup; objectName: "administratorCleanupTargets"; administrator: true; Layout.fillWidth: true; enabled: !worker.running && !manualCleanup.busy && !factoryReset.busy }
    SettingsCard {
        Layout.fillWidth: true
        title: "Automatic cleanup"
        subtitle: "Clean old user files on a systemd user timer. Missed runs are picked up at your next login. Save these settings separately below."
        enabled: page.loaded && !page.busy
        Label { text: "Schedule"; color: Style.Theme.muted }
        SettingsComboBox {
            model: ["Off", "Daily", "Weekly", "Monthly"]
            currentIndex: ["off", "daily", "weekly", "monthly"].indexOf(page.settings.schedule)
            onActivated: page.edit("schedule", ["off", "daily", "weekly", "monthly"][currentIndex])
        }
        SettingField {
            Layout.fillWidth: true
            label: "Only files untouched for this many days"
            value: String(page.settings.days)
            description: "1–365 days. Recently accessed, modified, or changed files are kept."
            onEdited: value => page.edit("days", /^\d+$/.test(value) ? Number(value) : value)
        }
        SettingField {
            Layout.fillWidth: true
            label: "Keep newest Hyprshell backup sets"
            value: String(page.settings.keep)
            description: "1–100 sets are always retained, even when older than the age limit."
            onEdited: value => page.edit("keep", /^\d+$/.test(value) ? Number(value) : value)
        }
        SettingsCheckBox { text: "Thumbnail cache (~/.cache/thumbnails or XDG cache directory)"; checked: page.settings.thumbnails; onToggled: page.edit("thumbnails", checked) }
        SettingsCheckBox { text: "Your old temporary files in /tmp and /var/tmp"; checked: page.settings.temporary; onToggled: page.edit("temporary", checked) }
        SettingsCheckBox { text: "Old Hyprshell config backups"; checked: page.settings.backups; onToggled: page.edit("backups", checked) }
        RowLayout {
            SettingsButton { text: "Save cleanup settings"; highlighted: page.dirty; enabled: page.dirty; onClicked: page.request("save", JSON.stringify(page.settings)) }
            SettingsButton { text: "Discard edits"; visible: page.dirty; onClicked: page.request("status", "") }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Preview automatic cleanup rules"
        subtitle: "Checks only the saved thumbnail, temporary-file and backup rules, including their age and retention limits. To clean browser and other caches now, use the manual controls above."
        SettingsButton {
            text: page.busy ? "Working…" : "Preview scheduled cleanup rules…"
            enabled: page.loaded && !page.dirty && !page.busy
            onClicked: page.request("preview", "")
        }
        Label {
            Layout.fillWidth: true
            visible: page.preview !== null
            text: page.preview ? page.preview.entries.length + " files · " + (page.preview.bytes / 1048576).toFixed(2) + " MiB eligible" : ""
            color: Style.Theme.text
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            visible: page.preview !== null
            clip: true
            TextArea {
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Style.Theme.text
                background: Rectangle { radius: Style.Theme.controlRadius; color: Style.Theme.field; border.color: Style.Theme.controlBorder }
                text: page.preview ? page.preview.entries.map(e => e.category + " · " + e.size + " bytes\n" + e.path).join("\n\n") || "No files match the saved age and backup-retention rules. This does not mean your browser or package caches are empty. Use Clean now · your files above to preview those caches." : ""
            }
        }
        RowLayout {
            visible: page.preview !== null
            SettingsButton {
                text: "Delete previewed files"
                enabled: !page.busy && page.preview !== null && page.preview.entries.length > 0
                onClicked: page.request("clean", page.preview.token)
            }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.preview = null }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Automatic cleanup status"
        subtitle: "The user cleanup timer and the distribution's existing package-cache timer keep their separate policies. Manual system maintenance is available above."
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "paccache.timer: " + page.paccache; color: Style.Theme.text }
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Hyprshell cleanup timer: " + page.timerStatus; color: Style.Theme.muted }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Personal data and installed software"
        subtitle: "The categories above cover disposable files and reviewed recovery history."
        SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Downloads, documents, browser profiles, credentials, repositories, personal-file backups, Windows VM disks and container volumes are preserved. They may use substantial storage, but can contain your work. Unused apps, VM disks and container resources should be removed through the application that manages them."; color: Style.Theme.muted }
        SettingsButton { text: "Open home folder for manual review"; onClicked: Qt.openUrlExternally("file://" + Quickshell.env("HOME").split("/").map(encodeURIComponent).join("/")) }
    }
    SettingsFactoryReset { id: factoryReset; Layout.fillWidth: true; ready: page.resetReady; enabled: !worker.running && !manualCleanup.busy && !systemCleanup.busy; onRestored: settings => page.restored(settings) }
    Label { Layout.fillWidth: true; text: page.message; wrapMode: Text.WrapAnywhere; color: Style.Theme.warning }
}
