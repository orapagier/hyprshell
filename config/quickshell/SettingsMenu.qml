import QtQuick
import "style" as Style
import QtQuick.Layouts

ColumnLayout {
    id: menu
    signal openRequested()
    spacing: 16
    implicitHeight: 126
    MenuLabel { text: "Make this desktop yours"; font.pixelSize: 15; font.bold: true }
    MenuLabel {
        Layout.fillWidth: true
        text: "Arrange your bar, personalize its colors, and fine-tune Hyprland."
        wrapMode: Text.WordWrap
        color: Style.Theme.muted
    }
    SettingsButton {
        objectName: "openSettingsButton"
        Layout.fillWidth: true
        text: "Open Hyprshell Settings  →"
        highlighted: true
        onClicked: menu.openRequested()
    }
}
