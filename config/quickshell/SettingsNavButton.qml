import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

Button {
    id: control
    property string symbol: "󰒓"
    property string hint: ""
    property bool itemEnabled: true
    property bool keyboardSelected: false
    implicitHeight: Math.max(Style.SettingsTheme.navRowHeight, contentItem.implicitHeight + 12)
    leftPadding: 10; rightPadding: 10
    hoverEnabled: true
    Accessible.name: text
    Accessible.description: highlighted ? "Current page" : itemEnabled ? hint : "Bar item is hidden"
    readonly property bool truncated: labelText.truncated
    contentItem: RowLayout {
        spacing: 11
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Style.SettingsTheme.iconBadgeSize
            implicitHeight: Style.SettingsTheme.iconBadgeSize
            radius: width / 2
            color: control.highlighted ? Style.SettingsTheme.iconBadgeActive : Style.SettingsTheme.iconBadge
            border.width: Style.SettingsTheme.highContrast ? 1 : 0
            border.color: Style.SettingsTheme.highContrast ? Style.SettingsTheme.controlBorder : "transparent"
            Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, Style.SettingsTheme.hoverDuration) } }
            Text {
                anchors.centerIn: parent
                text: control.symbol
                color: control.highlighted ? Style.SettingsTheme.iconBadgeTextActive : Style.SettingsTheme.iconBadgeText
                font.family: "GoMono Nerd Font"; font.pixelSize: Math.round(17 * Style.SettingsTheme.textScale)
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1
            Text {
                id: labelText
                Layout.fillWidth: true
                text: control.text
                font.pixelSize: Style.SettingsTheme.bodySize
                font.weight: control.highlighted ? Font.DemiBold : Font.Medium
                color: control.itemEnabled ? Style.SettingsTheme.text : Style.SettingsTheme.disabled
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: control.hint.length > 0
                text: control.hint
                font.pixelSize: Style.SettingsTheme.navHintSize
                color: control.itemEnabled ? Style.SettingsTheme.muted : Style.SettingsTheme.disabled
                elide: Text.ElideRight
            }
        }
    }
    background: Rectangle {
        radius: control.highlighted ? 16 : 12
        color: control.highlighted ? Style.SettingsTheme.navSelected : control.hovered ? Style.SettingsTheme.hover : "transparent"
        border.width: control.activeFocus || control.keyboardSelected ? 2 : 0
        border.color: (control.activeFocus || control.keyboardSelected) ? Style.SettingsTheme.accentText : "transparent"
        Behavior on radius { NumberAnimation { duration: Style.SettingsTheme.duration(control, 180); easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, Style.SettingsTheme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.SettingsTheme.effectsCurve } }
        scale: control.down ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Style.SettingsTheme.duration(control, 160); easing.type: Easing.OutCubic } }
    }
}
