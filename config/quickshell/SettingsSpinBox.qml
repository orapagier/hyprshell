import QtQuick
import QtQuick.Controls.Basic
import "style" as Style

SpinBox {
    id: control
    implicitHeight: Style.SettingsTheme.controlHeight
    font.pixelSize: Style.SettingsTheme.bodySize
    palette.base: Style.SettingsTheme.field
    palette.text: Style.SettingsTheme.text
    palette.button: Style.SettingsTheme.button
    palette.buttonText: Style.SettingsTheme.text
    palette.highlight: Style.SettingsTheme.selection
    palette.highlightedText: Style.SettingsTheme.text
    opacity: enabled ? 1 : 0.5
    up.indicator: Rectangle {
        x: control.mirrored ? 0 : control.width - width
        height: control.height; implicitWidth: 32
        radius: 10
        color: control.up.pressed ? Style.SettingsTheme.pressed : control.up.hovered ? Style.SettingsTheme.hover : "transparent"
        Text { anchors.centerIn: parent; text: "+"; color: Style.SettingsTheme.text; font.pixelSize: 18 }
    }
    down.indicator: Rectangle {
        x: control.mirrored ? control.width - width : 0
        height: control.height; implicitWidth: 32
        radius: 10
        color: control.down.pressed ? Style.SettingsTheme.pressed : control.down.hovered ? Style.SettingsTheme.hover : "transparent"
        Text { anchors.centerIn: parent; text: "−"; color: Style.SettingsTheme.text; font.pixelSize: 18 }
    }
    background: Rectangle {
        radius: 10
        color: Style.SettingsTheme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.highContrast ? Style.SettingsTheme.controlBorder : Style.SettingsTheme.border
    }
}
