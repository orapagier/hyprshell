import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

CheckBox {
    id: control
    implicitHeight: 38
    opacity: enabled ? 1 : 0.45
    spacing: 10
    indicator: Rectangle {
        implicitWidth: 22; implicitHeight: 22
        x: control.leftPadding; y: (control.height - height) / 2
        radius: 5
        color: control.checked ? Style.SettingsTheme.accent : Style.SettingsTheme.button
        border.color: control.activeFocus ? Style.SettingsTheme.accentText : control.checked ? Style.SettingsTheme.accentText : Style.SettingsTheme.controlBorder
        Text { anchors.centerIn: parent; text: "✓"; color: Style.SettingsTheme.accentForeground; font.pixelSize: 14; visible: control.checked }
    }
    contentItem: Text { text: control.text; font.pixelSize: Style.SettingsTheme.bodySize; color: Style.SettingsTheme.muted; leftPadding: control.indicator.width + control.spacing; verticalAlignment: Text.AlignVCenter }
}
