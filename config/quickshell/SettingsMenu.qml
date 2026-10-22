import QtQuick
import "AdaptiveColors.js" as Colors
import "style" as Style
import QtQuick.Layouts

ColumnLayout {
    id: menu
    readonly property var menuColors: Colors.menuColorsFor(menu)
    signal openRequested()
    spacing: 16
    implicitHeight: 126
    MenuLabel { text: "Make this desktop yours"; font.pixelSize: 15; font.bold: true }
    MenuLabel {
        Layout.fillWidth: true
        text: "Arrange your bar, personalize its colors, and fine-tune Hyprland."
        wrapMode: Text.WordWrap
        color: menu.menuColors.secondary
    }
    SettingsButton {
        id: openSettings
        objectName: "openSettingsButton"
        Layout.fillWidth: true
        text: "Open Hyprshell Settings  →"
        highlighted: true
        contentItem: Text {
            text: openSettings.text; font: openSettings.font
            color: menu.menuColors.text
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Style.Theme.controlRadius
            color: Colors.alpha(menu.menuColors.accent, openSettings.down ? 0.33 : openSettings.hovered ? 0.22 : 0.12)
            border.width: openSettings.activeFocus ? 2 : 1
            border.color: menu.menuColors.accent
            Behavior on color { ColorAnimation { duration: Style.Theme.duration(openSettings, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
        }
        onClicked: menu.openRequested()
    }
}
