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
    background: Rectangle {
        radius: Style.Theme.controlRadius
        color: Style.Theme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.Theme.accentText : Style.Theme.controlBorder
    }
}
