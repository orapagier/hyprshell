pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "style" as Style

PanelWindow {
    id: window
    property string error: ""
    readonly property bool busy: worker.running
    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-projector"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    function open() {
        error = "";
        visible = true;
        Qt.callLater(() => duplicateButton.forceActiveFocus());
    }
    function choose(layout) {
        if (worker.running) return;
        error = "";
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/displays.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify({operation: "project", layout: layout})];
        worker.running = true;
    }
    Process {
        id: worker
        objectName: "projectorWorker"
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (result.ok) window.visible = false;
                    else window.error = result.message || "Could not change displays.";
                } catch (e) { window.error = "Could not change displays."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) window.error = text.trim() }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: window.visible = false
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(320, window.width - 40)
        height: contents.implicitHeight + 40
        radius: 22
        color: Style.Theme.background
        border.color: Style.Theme.border
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: contents
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 12
            Label {
                text: "Projector options"
                color: Style.Theme.text
                font.pixelSize: Style.Theme.sectionSize
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                SettingsButton {
                    id: duplicateButton
                    objectName: "duplicateDisplays"
                    text: "Duplicate"
                    Layout.fillWidth: true
                    enabled: !worker.running
                    KeyNavigation.priority: KeyNavigation.BeforeItem
                    KeyNavigation.left: extendButton
                    KeyNavigation.right: extendButton
                    KeyNavigation.up: extendButton
                    KeyNavigation.down: extendButton
                    Keys.onReturnPressed: event => { window.choose("duplicate"); event.accepted = true; }
                    Keys.onEnterPressed: event => { window.choose("duplicate"); event.accepted = true; }
                    onClicked: window.choose("duplicate")
                }
                SettingsButton {
                    id: extendButton
                    objectName: "extendDisplays"
                    text: "Extend"
                    Layout.fillWidth: true
                    enabled: !worker.running
                    KeyNavigation.priority: KeyNavigation.BeforeItem
                    KeyNavigation.left: duplicateButton
                    KeyNavigation.right: duplicateButton
                    KeyNavigation.up: duplicateButton
                    KeyNavigation.down: duplicateButton
                    Keys.onReturnPressed: event => { window.choose("extend"); event.accepted = true; }
                    Keys.onEnterPressed: event => { window.choose("extend"); event.accepted = true; }
                    onClicked: window.choose("extend")
                }
            }
            Label {
                visible: !!window.error
                text: window.error
                color: Style.Theme.danger
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
    Shortcut { sequence: "Escape"; enabled: window.visible; onActivated: window.visible = false }
}
