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
        implicitWidth: 46; implicitHeight: 26
        x: control.width - width - control.rightPadding; y: (control.height - height) / 2
        radius: 13
        color: control.checked ? Style.Theme.accent : Style.Theme.controlBorder
        border.width: control.activeFocus ? 2 : 0
        border.color: Style.Theme.accentText
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, 140) } }
        Rectangle {
            x: control.checked ? parent.width - width - 3 : 3
            y: 3; width: 20; height: 20; radius: 10
            color: Style.Theme.accentForeground
            Behavior on x { NumberAnimation { duration: Style.Theme.duration(control, 260); easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
        }
    }
    contentItem: Text {
        text: control.text; font.pixelSize: Style.Theme.bodySize; color: Style.Theme.text
        rightPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
