import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

Switch {
    id: control
    implicitHeight: 40
    opacity: enabled ? 1 : 0.45
    spacing: 12
    hoverEnabled: true
    indicator: Rectangle {
        implicitWidth: 42; implicitHeight: 24
        x: control.width - width - control.rightPadding; y: (control.height - height) / 2
        radius: 12
        color: control.checked ? Style.SettingsTheme.accent : Style.SettingsTheme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus || control.checked ? Style.SettingsTheme.accentText : Style.SettingsTheme.controlBorder
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, 140) } }
        Rectangle {
            x: control.checked ? parent.width - width - 3 : 3
            y: 3; width: 18; height: 18; radius: 9
            color: control.checked ? Style.SettingsTheme.accentForeground : Style.SettingsTheme.text
            Behavior on x { NumberAnimation { duration: Style.SettingsTheme.duration(control, 180); easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Text {
        text: control.text; font.pixelSize: Style.SettingsTheme.bodySize; color: Style.SettingsTheme.text
        textFormat: Text.PlainText
        rightPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
