import QtQuick
import QtQuick.Controls.Basic
import "style" as Style

SpinBox {
    id: control
    implicitHeight: Style.Theme.controlHeight
    font.pixelSize: Style.Theme.bodySize
    palette.base: Style.Theme.field
    palette.text: Style.Theme.text
    palette.button: Style.Theme.button
    palette.buttonText: Style.Theme.text
    palette.highlight: Style.Theme.selection
    palette.highlightedText: Style.Theme.text
    opacity: enabled ? 1 : 0.5
    up.indicator: Rectangle {
        x: control.mirrored ? 0 : control.width - width
        height: control.height; implicitWidth: 32
        radius: 10
        color: control.up.pressed ? Style.Theme.pressed : control.up.hovered ? Style.Theme.hover : "transparent"
        Text { anchors.centerIn: parent; text: "+"; color: Style.Theme.text; font.pixelSize: 18 }
    }
    down.indicator: Rectangle {
        x: control.mirrored ? control.width - width : 0
        height: control.height; implicitWidth: 32
        radius: 10
        color: control.down.pressed ? Style.Theme.pressed : control.down.hovered ? Style.Theme.hover : "transparent"
        Text { anchors.centerIn: parent; text: "−"; color: Style.Theme.text; font.pixelSize: 18 }
    }
    background: Rectangle {
        radius: 10
        color: Style.Theme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.Theme.accentText : Style.Theme.highContrast ? Style.Theme.controlBorder : Style.Theme.border
    }
}
