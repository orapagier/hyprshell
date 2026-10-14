pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.Window
import "KeybindingsGuide.js" as Guide

ColumnLayout {
    id: page
    QtObject {
        id: theme
        readonly property color windowText: "#e2e6f3"
        readonly property color text: windowText
        readonly property color highlight: "#b4befe"
        readonly property color highlightedText: "#161824"
        readonly property color base: "#161824"
    }
    property var bindings: []
    property string error: ""
    readonly property var entries: Guide.matching(bindings, search.text)
    spacing: 12
    Timer { interval: 1500; running: true; repeat: true; onTriggered: if (!bindingReader.running) bindingReader.running = true }
    Process {
        id: bindingReader
        command: ["hyprctl", "-j", "binds"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let rows = JSON.parse(text);
                    if (!Array.isArray(rows)) throw new Error("Expected a binding list");
                    page.bindings = Guide.desktopBindings(rows);
                    page.error = "";
                } catch (e) { page.error = "Could not load keybindings"; }
            }
        }
        onExited: (code, status) => { if (code !== 0) page.error = "Could not load keybindings"; }
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
        onTextChanged: list.currentIndex = 0
        Keys.onDownPressed: { list.forceActiveFocus(); list.currentIndex = 0; }
    }
    ListView {
        id: list
        objectName: "keybindingsList"
        Layout.fillWidth: true
        Layout.fillHeight: true; Layout.minimumHeight: 120
        model: page.entries
        clip: true; spacing: 6
        keyNavigationEnabled: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool highlighted: hover.hovered || (list.activeFocus && list.currentIndex === index)
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
                    color: theme.windowText; opacity: 0.6
                    font.family: "Noto Sans"; font.pixelSize: 11; wrapMode: Text.Wrap
                }
                Flow {
                    width: parent.width; spacing: 5
                    Repeater {
                        model: row.modelData.shortcut.split(" + ")
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: keyLabel.implicitWidth + 14
                            implicitHeight: 24; radius: 6
                            color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.065)
                            border.color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.10)
                            Text { id: keyLabel; anchors.centerIn: parent; text: modelData; color: theme.windowText; opacity: 0.78; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }
        Column {
            anchors.centerIn: parent; width: parent.width; spacing: 8
            visible: !page.entries.length
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error || "No shortcuts found"; color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 14; font.weight: Font.Medium }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error ? "Try opening the panel again" : "Try a different action or key"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 12 }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.08) }
    RowLayout {
        Layout.fillWidth: true
        Text { text: page.entries.length + " of " + (page.bindings.length + Guide.localBindings.length) + " shortcuts"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: "↑ ↓  Browse   ·   Esc  Close"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 11 }
    }
}
