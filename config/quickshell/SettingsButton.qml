import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

Button {
    id: control
    implicitHeight: Style.Theme.controlHeight
    implicitWidth: Math.max(100, contentItem.implicitWidth + 36)
    leftPadding: 18; rightPadding: 18
    hoverEnabled: true
    font.pixelSize: Style.Theme.bodySize
    opacity: enabled ? 1 : 0.4
    contentItem: Text {
        text: control.text; font: control.font
        color: control.highlighted ? Style.Theme.accentForeground : Style.Theme.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 10
        color: control.highlighted ? (control.down ? Style.Theme.accentPressed : control.hovered ? Style.Theme.accentHover : Style.Theme.accent) : control.down ? Style.Theme.pressed : control.hovered ? Style.Theme.hover : control.flat ? "transparent" : Style.Theme.button
        border.color: control.activeFocus ? Style.Theme.accentText : Style.Theme.highContrast ? Style.Theme.border : "transparent"
        border.width: control.activeFocus ? 2 : Style.Theme.highContrast && !control.flat ? 1 : 0
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
        scale: control.down ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Style.Theme.duration(control, 220); easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
    }
}
