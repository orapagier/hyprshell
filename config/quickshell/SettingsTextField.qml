import QtQuick
import QtQuick.Controls.Basic
import "style" as Style

TextField {
    id: control
    implicitHeight: Style.Theme.controlHeight
    leftPadding: 12; rightPadding: 12
    color: Style.Theme.text
    placeholderTextColor: Style.Theme.muted
    selectionColor: Style.Theme.selection
    selectedTextColor: Style.Theme.text
    font.pixelSize: Style.Theme.bodySize
    selectByMouse: true
    opacity: enabled ? 1 : 0.5
    background: Rectangle {
        radius: Style.Theme.controlRadius
        color: Style.Theme.field
        border.width: 1
        border.color: Style.Theme.controlBorder
    }
}
