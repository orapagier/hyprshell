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
        radius: 10
        color: Style.Theme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.Theme.accentText : Style.Theme.highContrast ? Style.Theme.controlBorder : Style.Theme.border
    }
}
