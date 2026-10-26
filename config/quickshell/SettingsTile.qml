pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

Button {
    id: tile
    property string symbol: "󰒓"
    property string description: ""
    implicitHeight: Math.max(100, contentItem.implicitHeight + 36)
    implicitWidth: 240
    padding: 20
    hoverEnabled: true
    Accessible.name: text
    Accessible.description: description
    contentItem: RowLayout {
        spacing: 16
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 38; implicitHeight: 38; radius: 12
            color: Style.SettingsTheme.selection
            Text {
                anchors.centerIn: parent
                text: tile.symbol; font.family: "GoMono Nerd Font"; font.pixelSize: 20
                color: Style.SettingsTheme.accentText
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                Layout.fillWidth: true
                text: tile.text; wrapMode: Text.WordWrap
                color: Style.SettingsTheme.text
                font.pixelSize: Style.SettingsTheme.bodySize; font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                text: tile.description; wrapMode: Text.WordWrap
                color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
            }
        }
        Label { text: "›"; color: tile.hovered ? Style.SettingsTheme.accentText : Style.SettingsTheme.disabled; font.pixelSize: 20 }
    }
    background: Rectangle {
        radius: Style.SettingsTheme.radius
        color: tile.down ? Style.SettingsTheme.pressed : tile.hovered ? Style.SettingsTheme.hover : Style.SettingsTheme.surface
        border.width: tile.activeFocus ? 2 : 1
        border.color: tile.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.highContrast ? Style.SettingsTheme.border : "transparent"
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(tile, 150) } }
    }
}
