pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "style" as Style

PanelWindow {
    id: window
    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-projector"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    function open() {
        visible = true;
        if (!page.busy) page.request("status");
    }
    MouseArea {
        anchors.fill: parent
        onClicked: window.visible = false
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, window.width - 40)
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
            SettingsDisplays {
                id: page
                objectName: "projectorPage"
                projectionOnly: true
                visible: window.visible
                Layout.fillWidth: true
            }
            SettingsButton {
                text: "Close · Esc"
                Layout.alignment: Qt.AlignRight
                onClicked: window.visible = false
            }
        }
    }
    Shortcut { sequence: "Escape"; enabled: window.visible; onActivated: window.visible = false }
}
