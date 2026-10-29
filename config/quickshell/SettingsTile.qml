pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

Button {
    id: tile
    property string symbol: "󰒓"
    property string description: ""
    implicitHeight: Math.max(108, contentItem.implicitHeight + 32)
    implicitWidth: 240
    padding: 18
    hoverEnabled: true
    Accessible.name: text
    Accessible.description: description
    contentItem: RowLayout {
        spacing: 14
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Math.round(44 * Style.SettingsTheme.textScale)
            implicitHeight: Math.round(44 * Style.SettingsTheme.textScale)
            radius: width / 2
            color: Style.SettingsTheme.iconBadge
            border.width: Style.SettingsTheme.highContrast ? 1 : 0
            border.color: Style.SettingsTheme.highContrast ? Style.SettingsTheme.controlBorder : "transparent"
            Text {
                anchors.centerIn: parent
                text: tile.symbol; font.family: "GoMono Nerd Font"; font.pixelSize: Math.round(21 * Style.SettingsTheme.textScale)
                color: Style.SettingsTheme.iconBadgeText
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
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
        radius: Style.SettingsTheme.cardRadius
        color: tile.down ? Style.SettingsTheme.pressed : tile.hovered ? Style.SettingsTheme.cardHover : Style.SettingsTheme.card
        border.width: tile.activeFocus || tile.hovered ? 1 : Style.SettingsTheme.highContrast ? 1 : 0
        border.color: tile.activeFocus ? Style.SettingsTheme.accentText : tile.hovered ? Style.SettingsTheme.controlBorder : Style.SettingsTheme.highContrast ? Style.SettingsTheme.border : "transparent"
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(tile, 150) } }
        scale: tile.down ? 0.99 : 1
        Behavior on scale { NumberAnimation { duration: Style.SettingsTheme.duration(tile, 160); easing.type: Easing.OutCubic } }
    }
}
