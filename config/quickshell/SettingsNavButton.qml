import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

Button {
    id: control
    property string symbol: "󰒓"
    property bool itemEnabled: true
    property bool keyboardSelected: false
    implicitHeight: Math.round(42 * Style.SettingsTheme.textScale)
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
            color: control.highlighted ? Style.SettingsTheme.accentText : Style.SettingsTheme.muted
            font.family: "GoMono Nerd Font"; font.pixelSize: 16
        }
        Text {
            id: labelText
            x: 33; width: parent.width - 33; anchors.verticalCenter: parent.verticalCenter
            text: control.text; font.pixelSize: Style.SettingsTheme.bodySize; font.weight: control.highlighted ? Font.DemiBold : Font.Normal
            color: control.itemEnabled ? Style.SettingsTheme.text : Style.SettingsTheme.disabled
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 10
        color: control.highlighted ? Style.SettingsTheme.selection : control.hovered ? Style.SettingsTheme.hover : "transparent"
        border.width: control.activeFocus || control.keyboardSelected ? 2 : 0
        border.color: (control.activeFocus || control.keyboardSelected) ? Style.SettingsTheme.accentText : Style.SettingsTheme.border
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, Style.SettingsTheme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.SettingsTheme.effectsCurve } }
        scale: control.down ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Style.SettingsTheme.duration(control, 160); easing.type: Easing.OutCubic } }
    }
}
