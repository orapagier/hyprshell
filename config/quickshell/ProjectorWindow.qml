pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import "style" as Style

FloatingWindow {
    id: window
    title: "Hyprshell Projector options"
    visible: false
    implicitWidth: 560
    implicitHeight: 440
    color: Style.Theme.background
    onClosed: visible = false
    function open() {
        visible = true;
        if (!page.busy) page.request("status");
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16
        SettingsDisplays {
            id: page
            objectName: "projectorPage"
            projectionOnly: true
            visible: window.visible
            Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }
        SettingsButton {
            text: "Close"
            Layout.alignment: Qt.AlignRight
            onClicked: window.visible = false
        }
    }
}
