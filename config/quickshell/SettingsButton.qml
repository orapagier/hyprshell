import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

Button {
    id: control
    implicitHeight: Style.SettingsTheme.controlHeight
    implicitWidth: Math.max(100, contentItem.implicitWidth + 36)
    leftPadding: 18; rightPadding: 18
    hoverEnabled: true
    font.pixelSize: Style.SettingsTheme.bodySize
    opacity: enabled ? 1 : 0.4
    contentItem: Text {
        text: control.text; font: control.font
        color: control.highlighted ? Style.SettingsTheme.accentForeground : Style.SettingsTheme.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 10
        color: control.highlighted ? (control.down ? Style.SettingsTheme.accentPressed : control.hovered ? Style.SettingsTheme.accentHover : Style.SettingsTheme.accent) : control.down ? Style.SettingsTheme.pressed : control.hovered ? Style.SettingsTheme.hover : control.flat ? "transparent" : Style.SettingsTheme.button
        border.color: control.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.highContrast ? Style.SettingsTheme.border : "transparent"
        border.width: control.activeFocus ? 2 : Style.SettingsTheme.highContrast && !control.flat ? 1 : 0
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, Style.SettingsTheme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.SettingsTheme.effectsCurve } }
        scale: control.down ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: Style.SettingsTheme.duration(control, 160); easing.type: Easing.OutCubic } }
    }
}
