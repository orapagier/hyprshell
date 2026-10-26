pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    required property var settings
    property string runtimeError: ""
    property bool available: false
    property bool revealed: false
    property bool confirmClear: false
    property var entries: []
    property string message: ""
    property bool success: true
    readonly property bool busy: worker.running
    signal edited(string key, var value)
    spacing: 16
    Component.onCompleted: request("status")
    function request(operation, ident) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/clipboard.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify({operation: operation, id: ident || "", confirmed: confirmClear})];
        worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector { onStreamFinished: {
            try {
                let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                if (result.available !== undefined) page.available = result.available;
                if (result.entries !== undefined) { page.entries = result.entries; page.revealed = true; }
                if (result.ok && result.removed) page.entries = page.entries.filter(row => row.id !== result.removed);
                page.confirmClear = false;
            } catch (e) { page.success = false; page.message = "Could not read clipboard controls. Refresh to retry."; }
        } }
    }
    SettingsCard {
        title: "Clipboard history"
        subtitle: "Disabled by default. When enabled, saves copied text locally; optional images use more storage. Applications must flag sensitive data to exclude it. Disable capture when copying secrets."
        Layout.fillWidth: true
        SettingsSwitch { objectName: "clipboardEnabled"; text: "Remember clipboard entries"; checked: page.settings.enabled; enabled: page.available || checked; Layout.fillWidth: true; onToggled: page.edited("enabled", checked) }
        SettingsSwitch { text: "Include images"; checked: page.settings.includeImages; Layout.fillWidth: true; onToggled: page.edited("includeImages", checked) }
        SettingsSlider { label: "Maximum saved entries"; settingValue: page.settings.maxItems; from: 10; to: 200; allowReset: false; Layout.fillWidth: true; onEdited: value => page.edited("maxItems", value) }
        SettingsLabel { text: "Entries are limited to 5 MiB each. The entry limit is enforced on the next capture. Disabling history stops capture and keeps saved entries until cleared. History never travels through GitHub sync."; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        SettingsButton { visible: !page.available; text: "Install clipboard tools…"; enabled: !page.busy; onClicked: page.request("install") }
        SettingsButton { text: "Refresh tool availability"; enabled: !page.busy; onClicked: page.request("status") }
    }
    SettingsCard {
        title: "Saved entries"
        subtitle: "History is read only when requested. Copy an entry here, then paste it into your app."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { objectName: "showClipboardHistory"; text: page.revealed ? "Refresh history" : "Show history"; enabled: page.available && !page.busy; onClicked: page.request("list") }
            SettingsButton { visible: page.revealed; text: "Hide history"; onClicked: { page.entries = []; page.revealed = false; } }
            SettingsButton { text: "Clear all…"; enabled: !page.busy; onClicked: page.confirmClear = true }
        }
        SettingsLabel { visible: page.confirmClear; text: "Permanently remove saved entries? This cannot be undone."; color: Style.SettingsTheme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
        RowLayout {
            visible: page.confirmClear
            SettingsButton { text: "Clear saved history"; enabled: !page.busy; onClicked: page.request("wipe") }
            SettingsButton { text: "Cancel"; onClicked: page.confirmClear = false }
        }
        SettingsLabel { visible: page.revealed && page.entries.length === 0; text: "History is empty."; color: Style.SettingsTheme.muted }
        Repeater {
            model: page.entries
            delegate: RowLayout {
                id: entryRow
                required property var modelData
                Layout.fillWidth: true
                SettingsLabel { text: entryRow.modelData.preview; textFormat: Text.PlainText; color: Style.SettingsTheme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                SettingsButton { text: "Copy"; enabled: !page.busy; onClicked: page.request("copy", entryRow.modelData.id) }
                SettingsButton { text: "Remove"; enabled: !page.busy; onClicked: page.request("delete", entryRow.modelData.id) }
            }
        }
    }
    SettingsLabel { text: [page.message, page.runtimeError].filter(Boolean).join("\n"); visible: text.length > 0; color: page.success && !page.runtimeError ? Style.SettingsTheme.success : Style.SettingsTheme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
