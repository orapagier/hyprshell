pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property var targetWindow: null
    property var entries: []
    property var bindings: []
    property var draft: ({id: "", original: "", shortcut: "", description: "", mode: "command", command: ""})
    property var initialDraft: ({})
    property bool editing: false
    property bool manualEntry: false
    property bool loaded: false
    property string message: ""
    property bool success: true
    property string operation: ""
    readonly property bool busy: worker.running
    readonly property bool dirty: editing && JSON.stringify(draft) !== JSON.stringify(initialDraft)
    readonly property string conflict: {
        let keys = draft.shortcut.trim().toUpperCase();
        let original = (initialDraft.shortcut || "").toUpperCase();
        return keys && keys !== original && bindings.some(b => b.shortcut.toUpperCase() === keys)
            ? "This combination is already in use." : "";
    }
    readonly property bool canSave: loaded && editing && dirty && !busy && !recorder.recording && !conflict && draft.shortcut.trim() !== "" && draft.description.trim() !== "" && (draft.mode === "existing" || draft.command.trim() !== "")
    readonly property var filtered: bindings.filter(b => filter.text.toLowerCase().trim().split(/\s+/).every(word => (b.shortcut + " " + b.description).toLowerCase().includes(word)))
    signal editorRequested()
    spacing: 16
    onVisibleChanged: {
        if (visible && !busy && !dirty) request({operation: "status"});
        if (!visible) recorder.cancel();
    }
    Component.onCompleted: if (visible) request({operation: "status"})
    function request(payload) {
        if (busy) return;
        operation = payload.operation;
        message = "";
        recorder.cancel();
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/keybindings.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function edit(key, value) {
        let next = Object.assign({}, draft); next[key] = value; draft = next;
    }
    function select(binding) {
        recorder.cancel();
        draft = Object.assign({}, binding);
        initialDraft = Object.assign({}, binding);
        editing = true; manualEntry = false; message = "";
        editorRequested();
    }
    function add() {
        select({id: "", original: "", shortcut: "", description: "", mode: "command", command: ""});
    }
    function closeEditor() { recorder.cancel(); editing = false; message = ""; }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    page.message = result.message || "";
                    if (result.ok) {
                        page.entries = result.entries;
                        page.bindings = result.bindings;
                        page.loaded = true;
                        if (page.operation === "save" || page.operation === "reset") page.editing = false;
                        if (page.message) noticeTimeout.restart();
                    }
                } catch (e) { page.success = false; page.message = "Could not read shortcuts. Try refreshing."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = text; } }
    }
    Timer { id: noticeTimeout; interval: 3500; onTriggered: if (page.success) page.message = "" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        TextField {
            id: filter
            objectName: "shortcutSearch"
            Layout.fillWidth: true
            implicitHeight: 42; leftPadding: 14; rightPadding: 14
            placeholderText: "Search shortcuts…"
            Accessible.name: "Search shortcuts"
            color: Style.SettingsTheme.text; placeholderTextColor: Style.SettingsTheme.muted
            font.family: "Noto Sans"; font.pixelSize: Style.SettingsTheme.bodySize
            selectByMouse: true
            background: Rectangle {
                radius: 10; color: Style.SettingsTheme.field
                border.color: Style.SettingsTheme.border
                Behavior on border.color { ColorAnimation { duration: Style.SettingsTheme.duration(filter, 140) } }
            }
        }
        SettingsButton { text: "+ New"; highlighted: true; enabled: page.loaded && !page.busy && !page.dirty; onClicked: page.add() }
        SettingsButton { text: "↻"; implicitWidth: 42; leftPadding: 10; rightPadding: 10; Accessible.name: "Refresh shortcuts"; enabled: !page.busy && !page.dirty; onClicked: page.request({operation: "status"}) }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: page.editing
        title: page.draft.original ? "Edit shortcut" : "New shortcut"
        enabled: page.loaded && !page.busy
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Shortcut"; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.bodySize }
            ShortcutRecorder {
                id: recorder
                objectName: "shortcutRecorder"
                Layout.fillWidth: true
                targetWindow: page.targetWindow
                value: page.draft.shortcut
                onRecorded: shortcut => { page.edit("shortcut", shortcut); page.manualEntry = false; }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { visible: !!page.conflict; text: page.conflict; color: Style.SettingsTheme.danger; font.pixelSize: Style.SettingsTheme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Item { visible: !page.conflict; Layout.fillWidth: true }
                Button {
                    text: page.manualEntry ? "Hide manual entry" : "Enter manually"
                    flat: true; font.pixelSize: Style.SettingsTheme.captionSize
                    enabled: !recorder.recording
                    onClicked: page.manualEntry = !page.manualEntry
                    contentItem: Text { text: parent.text; color: Style.SettingsTheme.muted; font: parent.font }
                    background: Item {}
                }
            }
            TextField {
                visible: page.manualEntry
                Layout.fillWidth: true
                implicitHeight: 40; leftPadding: 12
                text: page.draft.shortcut; placeholderText: "SUPER + SHIFT + N"
                color: Style.SettingsTheme.text; selectByMouse: true
                Accessible.name: "Enter shortcut manually"
                background: Rectangle { radius: 8; color: Style.SettingsTheme.field; border.color: Style.SettingsTheme.border }
                onTextEdited: page.edit("shortcut", text)
            }
        }
        SettingField {
            Layout.fillWidth: true
            label: "Action"; value: page.draft.description; hint: "Open notes"
            enabled: !recorder.recording
            onEdited: value => page.edit("description", value)
        }
        SettingsComboBox {
            Layout.fillWidth: true
            visible: page.draft.original !== ""
            enabled: !recorder.recording
            model: ["Keep existing action", "Run a command"]
            currentIndex: page.draft.mode === "existing" ? 0 : 1
            onActivated: {
                page.edit("mode", currentIndex === 0 ? "existing" : "command");
                if (currentIndex === 0) page.edit("command", "");
            }
        }
        SettingField {
            Layout.fillWidth: true
            visible: page.draft.mode === "command"
            enabled: !recorder.recording
            label: "Command"; value: page.draft.command; hint: "uwsm app -- kitty"
            onEdited: value => page.edit("command", value)
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            SettingsButton {
                objectName: "saveShortcutButton"
                text: page.busy ? "Saving…" : "Save shortcut"
                highlighted: true; enabled: page.canSave
                onClicked: page.request({operation: "save", expected: page.entries, entry: page.draft})
            }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.closeEditor() }
            SettingsButton {
                visible: page.draft.id !== ""
                text: page.draft.original ? "Restore" : "Remove"
                flat: true; enabled: !recorder.recording
                onClicked: page.request({operation: "reset", expected: page.entries, id: page.draft.id})
            }
        }
    }
    Label {
        Layout.fillWidth: true
        visible: page.message !== ""
        text: page.message
        color: page.success ? Style.SettingsTheme.success : Style.SettingsTheme.danger
        wrapMode: Text.Wrap
        font.pixelSize: Style.SettingsTheme.bodySize
    }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Your shortcuts"; color: Style.SettingsTheme.text; font.family: "Noto Sans"; font.pixelSize: Style.SettingsTheme.bodySize; font.weight: Font.Medium; Layout.fillWidth: true }
        Label { text: page.busy && !page.loaded ? "Loading…" : String(page.filtered.length); color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize }
    }
    ListView {
        id: list
        objectName: "shortcutList"
        Layout.fillWidth: true; Layout.preferredHeight: 390
        clip: true; spacing: 4
        model: page.filtered
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: ItemDelegate {
            id: row
            required property var modelData
            width: list.width
            height: contents.implicitHeight + 24
            enabled: !page.busy && !page.dirty && !recorder.recording
            hoverEnabled: true
            onClicked: page.select(modelData)
            background: Rectangle {
                radius: 10
                color: row.hovered ? Style.SettingsTheme.hover : Style.SettingsTheme.field
                border.color: row.activeFocus ? Style.SettingsTheme.accentText : "transparent"
                Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(row, 120) } }
            }
            contentItem: ColumnLayout {
                id: contents
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: row.modelData.description; color: Style.SettingsTheme.text; font.family: "Noto Sans"; font.pixelSize: Style.SettingsTheme.bodySize; Layout.fillWidth: true; elide: Text.ElideRight }
                    Rectangle { visible: !!row.modelData.id; width: 5; height: 5; radius: 3; color: Style.SettingsTheme.accentText }
                    Label { text: "›"; color: Style.SettingsTheme.muted; font.pixelSize: 18 }
                }
                ShortcutBadges { Layout.fillWidth: true; shortcut: row.modelData.shortcut; fill: Style.SettingsTheme.button; outline: Style.SettingsTheme.border }
            }
        }
        Column {
            anchors.centerIn: parent; spacing: 6
            visible: page.loaded && !page.filtered.length
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "No shortcuts found"; color: Style.SettingsTheme.text; font.pixelSize: Style.SettingsTheme.bodySize }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "Try another search"; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize }
        }
    }
}
