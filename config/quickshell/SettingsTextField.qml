import QtQuick
import QtQuick.Controls.Basic
import "style" as Style

TextField {
    id: control
    implicitHeight: Style.SettingsTheme.controlHeight
    leftPadding: 12; rightPadding: 12
    color: Style.SettingsTheme.text
    placeholderTextColor: Style.SettingsTheme.muted
    selectionColor: Style.SettingsTheme.selection
    selectedTextColor: Style.SettingsTheme.text
    font.pixelSize: Style.SettingsTheme.bodySize
    selectByMouse: true
    opacity: enabled ? 1 : 0.5
    background: Rectangle {
        radius: Style.SettingsTheme.fieldRadius
        color: control.activeFocus ? Style.SettingsTheme.field : control.hovered ? Style.SettingsTheme.hover : Style.SettingsTheme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.highContrast ? Style.SettingsTheme.controlBorder : Style.SettingsTheme.border
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, Style.SettingsTheme.hoverDuration) } }
    }
}
