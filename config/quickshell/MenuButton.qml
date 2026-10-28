import QtQuick
import "style" as Style
import "AdaptiveColors.js" as Colors
import QtQuick.Controls

Button {
    id: control
    readonly property var menuColors: Colors.menuColorsFor(control)
    // Drawers can opt into pill controls without changing other menus.
    property bool pillShape: {
        for (let item = parent; item; item = item.parent)
            if (item.roundedMenuButtons !== undefined) return item.roundedMenuButtons;
        return false;
    }
    hoverEnabled: true
    scale: down ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: Style.Theme.duration(control, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
    property color accent: menuColors.text
    property color fillColor: "#0bffffff"
    property color hoverColor: menuColors.hover
    property color pressedColor: menuColors.pressed
    property color outlineColor: "#1fffffff"
    property color focusColor: menuColors.focus
    implicitHeight: Math.max(36, contentItem.implicitHeight + 16)
    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
    font.family: "DejaVu Sans"; font.pixelSize: 13
    contentItem: Text {
        text: control.text
        // Device names, application labels and notification actions are data.
        textFormat: Text.PlainText
        font: control.font
        color: control.enabled ? control.accent : control.menuColors.disabled
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: control.pillShape ? height / 2 : control.down ? 10 : control.hovered ? 14 : 8
        color: control.down ? control.pressedColor : control.hovered || control.activeFocus ? control.hoverColor : control.fillColor
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
        Behavior on radius { NumberAnimation { duration: Style.Theme.duration(control, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
        border.width: 1; border.color: control.activeFocus ? control.focusColor : control.outlineColor
    }
}
