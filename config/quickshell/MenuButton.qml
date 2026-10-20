import QtQuick
import "style" as Style
import QtQuick.Controls

Button {
    id: control
    hoverEnabled: true
    scale: down ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: Style.Theme.duration(control, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
    property color accent: "#cdd6f4"
    property color fillColor: "#0bffffff"
    property color hoverColor: "#38cba6f7"
    property color pressedColor: "#55cba6f7"
    property color outlineColor: "#1fffffff"
    property color focusColor: "#88cba6f7"
    implicitHeight: Math.max(36, contentItem.implicitHeight + 16)
    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
    font.family: "DejaVu Sans"; font.pixelSize: 13
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? control.accent : "#585b70"
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: control.down ? 10 : control.hovered ? 14 : 8
        color: control.down ? control.pressedColor : control.hovered || control.activeFocus ? control.hoverColor : control.fillColor
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
        Behavior on radius { NumberAnimation { duration: Style.Theme.duration(control, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
        border.width: 1; border.color: control.activeFocus ? control.focusColor : control.outlineColor
    }
}
