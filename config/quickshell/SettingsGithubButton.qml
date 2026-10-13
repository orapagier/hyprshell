import QtQuick
import "style" as Style

SettingsButton {
    id: control
    contentItem: Row {
        spacing: 8
        Text {
            text: "\uf09b"
            font.family: "GoMono Nerd Font"
            font.pixelSize: 18
            color: Style.Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            font: control.font
            color: Style.Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Accessible.name: text
}
