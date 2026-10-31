pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.Window
import "KeybindingsGuide.js" as Guide

ColumnLayout {
    id: page
    property bool fitContent: false
    readonly property var menuColors: Colors.menuColorsFor(page)
    QtObject {
        id: theme
        readonly property color windowText: page.menuColors.text
        readonly property color text: windowText
        readonly property color highlight: page.menuColors.accent
        readonly property color highlightedText: page.menuColors.background
        readonly property color base: page.menuColors.background
    }
    property var bindings: []
    property string error: ""
    property string registryJson: ""
    property string registryText: ""
    property string acceptedRegistry: ""
    property var pendingRows: []
    function acceptRegistry(rows, text) {
        let signature = registryJson + "\n" + text;
        if (signature !== acceptedRegistry) {
            bindings = Guide.desktopBindings(text === null ? rows : Guide.namedBindings(rows, text));
            acceptedRegistry = signature;
        }
        error = "";
    }
    readonly property var entries: Guide.matching(bindings, search.text)
    function moveSelection(step) {
        if (!entries.length) return;
        list.currentIndex = list.currentIndex < 0 ? 0
            : Math.max(0, Math.min(entries.length - 1, list.currentIndex + step));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    spacing: 12
    // Runtime bind/unbind commands need not emit configreloaded. Retain live
    // detection while open, without launching Python or rebuilding unchanged rows.
    Timer { interval: 1500; running: true; repeat: true; onTriggered: if (!bindingReader.running && !nameReader.running) bindingReader.running = true }
    // Preserve the helper's per-query timeout without extra timeout processes.
    Timer { interval: 5000; running: bindingReader.running; onTriggered: bindingReader.signal(9) }
    Timer { interval: 5000; running: nameReader.running; onTriggered: nameReader.signal(9) }
    Process {
        id: bindingReader
        command: ["hyprctl", "-j", "binds"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.registryJson = text }
        onExited: (code, status) => {
            if (code !== 0) { page.error = "Could not load keybindings"; return; }
            try {
                let rows = JSON.parse(page.registryJson);
                if (!Array.isArray(rows)) throw new Error("Expected a binding list");
                if (rows.some(row => !row.key && !row.keycode && !row.catch_all)) {
                    page.pendingRows = rows;
                    nameReader.running = true;
                } else page.acceptRegistry(rows, null);
            } catch (e) { page.error = "Could not load keybindings"; }
        }
    }
    Process {
        id: nameReader
        command: ["hyprctl", "binds"]
        stdout: StdioCollector { onStreamFinished: page.registryText = text }
        onExited: (code, status) => {
            if (code !== 0) { page.error = "Could not load keybindings"; return; }
            try {
                page.acceptRegistry(page.pendingRows, page.registryText);
            } catch (e) { page.error = "Could not load keybindings"; }
        }
    }
    Text {
        objectName: "keybindingsError"
        Layout.fillWidth: true
        visible: !!page.error
        text: page.error + ". Desktop shortcuts could not be refreshed; " + (page.bindings.length ? "showing the last successful list." : "only local controls are shown.")
        color: "#f38ba8"; wrapMode: Text.Wrap
        font.family: "Noto Sans"; font.pixelSize: 12
    }
    TextField {
        id: search
        objectName: "keybindingsSearch"
        Layout.fillWidth: true
        implicitHeight: 46
        leftPadding: 15; rightPadding: 15
        placeholderText: "Search an action or key combination…"
        color: theme.text
        placeholderTextColor: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.45)
        font.family: "Noto Sans"; font.pixelSize: 13
        selectionColor: theme.highlight
        selectedTextColor: theme.highlightedText
        background: Rectangle {
            radius: 12
            color: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.65)
            border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.12)
            Behavior on border.color { ColorAnimation { duration: 140 } }
        }
        Component.onCompleted: forceActiveFocus()
        onTextChanged: {
            list.currentIndex = page.entries.length ? 0 : -1;
            list.positionViewAtBeginning();
        }
        Keys.onDownPressed: page.moveSelection(1)
        Keys.onUpPressed: page.moveSelection(-1)
    }
    ListView {
        id: list
        objectName: "keybindingsList"
        Layout.fillWidth: true
        Layout.fillHeight: true; Layout.minimumHeight: 120
        Layout.preferredHeight: page.fitContent ? Math.max(120, Math.min(520, list.contentHeight)) : -1
        model: page.entries
        clip: true; spacing: 6
        keyNavigationEnabled: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool highlighted: hover.hovered || ((list.activeFocus || search.activeFocus) && list.currentIndex === index)
            width: list.width
            height: labels.implicitHeight + 24
            radius: 12
            color: highlighted ? Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.12) : Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.035)
            border.color: highlighted ? Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.24) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: hover }
            Column {
                id: labels
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                spacing: 9
                Text {
                    width: parent.width; text: row.modelData.action
                    color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 13; font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: row.modelData.context + (row.modelData.details ? " · " + row.modelData.details : "")
                    color: theme.windowText; opacity: 0.82
                    font.family: "Noto Sans"; font.pixelSize: 11; wrapMode: Text.Wrap
                }
                Flow {
                    width: parent.width; spacing: 5
                    Repeater {
                        model: row.modelData.keyLabels && row.modelData.keyLabels.length > 1 ? row.modelData.keyLabels : row.modelData.shortcut.split(" + ")
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: keyLabel.implicitWidth + 14
                            implicitHeight: 24; radius: 6
                            color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.065)
                            border.color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.10)
                            Text { id: keyLabel; anchors.centerIn: parent; text: modelData; color: theme.windowText; opacity: 0.88; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }
        Column {
            anchors.centerIn: parent; width: parent.width; spacing: 8
            visible: !page.entries.length
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error || "No shortcuts found"; color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 14; font.weight: Font.Medium }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error ? "Try opening the panel again" : "Try a different action or key"; color: theme.windowText; opacity: 0.82; font.family: "Noto Sans"; font.pixelSize: 12 }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.08) }
    RowLayout {
        Layout.fillWidth: true
        Text { text: page.entries.length + " of " + (page.bindings.length + Guide.localBindings.length) + " shortcuts"; color: theme.windowText; opacity: 0.82; font.family: "Noto Sans"; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: "↑ ↓  Browse   ·   Esc  Close"; color: theme.windowText; opacity: 0.82; font.family: "Noto Sans"; font.pixelSize: 11 }
    }
}
