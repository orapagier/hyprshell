import QtQuick
import "style" as Style

SettingsButton {
    id: control
    contentItem: Row {
        spacing: 8
        Text {
            text: "\uf09b"
            font.family: "GoMono Nerd Font"
            font.pixelSize: 17
            color: control.highlighted ? Style.SettingsTheme.accentForeground : Style.SettingsTheme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            font: control.font
            color: control.highlighted ? Style.SettingsTheme.accentForeground : Style.SettingsTheme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Accessible.name: text
}
