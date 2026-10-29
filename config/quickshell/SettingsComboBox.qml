import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

ComboBox {
    id: control
    implicitHeight: Style.SettingsTheme.controlHeight
    implicitWidth: Math.max(116, contentItem.implicitWidth + 54)
    leftPadding: 14; rightPadding: 34
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    font.pixelSize: Style.SettingsTheme.bodySize
    contentItem: Text {
        text: control.displayText; font: control.font; color: Style.SettingsTheme.text
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    indicator: Text { text: "⌄"; color: Style.SettingsTheme.muted; font.pixelSize: 18; x: control.width - 26; y: (control.height - height) / 2 - 2 }
    background: Rectangle {
        radius: Style.SettingsTheme.fieldRadius; color: control.hovered ? Style.SettingsTheme.hover : Style.SettingsTheme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.highContrast ? Style.SettingsTheme.controlBorder : Style.SettingsTheme.border
        Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(control, 130) } }
    }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: control.width - 12; height: 38
        highlighted: control.highlightedIndex === index
        contentItem: Text { text: modelData; textFormat: Text.PlainText; color: Style.SettingsTheme.text; font.pixelSize: Style.SettingsTheme.bodySize; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { radius: Style.SettingsTheme.fieldRadius; color: parent.highlighted ? Style.SettingsTheme.navSelected : "transparent" }
    }
    popup: Popup {
        y: control.height + 6; width: control.width
        padding: 6
        implicitHeight: Math.min(240, list.contentHeight + 12)
        transformOrigin: Item.Top
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.SettingsTheme.duration(control, 120) }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Style.SettingsTheme.duration(control, 220); easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Style.SettingsTheme.duration(control, 90) }
        }
        background: Rectangle { radius: Style.SettingsTheme.cardRadius; color: Style.SettingsTheme.surface; border.color: Style.SettingsTheme.border }
        contentItem: ListView {
            id: list
            clip: true; implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
