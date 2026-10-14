import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

Button {
    id: control
    property string symbol: "󰒓"
    property bool itemEnabled: true
    property bool keyboardSelected: false
    implicitHeight: 42
    leftPadding: 13; rightPadding: 13
    hoverEnabled: true
    Accessible.name: text
    Accessible.description: highlighted ? "Current page" : itemEnabled ? "" : "Bar item is hidden"
    ToolTip.visible: (hovered || activeFocus) && truncated
    ToolTip.text: text
    readonly property bool truncated: labelText.truncated
    contentItem: Item {
        implicitWidth: 180; implicitHeight: 24
        Text {
            text: control.symbol; width: 22; anchors.verticalCenter: parent.verticalCenter
            color: control.highlighted ? Style.Theme.text : Style.Theme.muted
            font.family: "GoMono Nerd Font"; font.pixelSize: 16
        }
        Text {
            id: labelText
            x: 33; width: parent.width - 33; anchors.verticalCenter: parent.verticalCenter
            text: control.text; font.pixelSize: Style.Theme.bodySize; font.weight: control.highlighted ? Font.DemiBold : Font.Normal
            color: control.itemEnabled ? Style.Theme.text : Style.Theme.disabled
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 8
        color: control.highlighted ? Style.Theme.selection : control.hovered ? Style.Theme.button : "transparent"
        border.width: control.activeFocus || control.keyboardSelected ? 2 : 0
        border.color: (control.activeFocus || control.keyboardSelected) ? Style.Theme.accentText : Style.Theme.border
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, 140) } }
    }
}
