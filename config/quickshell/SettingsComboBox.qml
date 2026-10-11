import QtQuick
import "style" as Style
import QtQuick.Controls.Basic

ComboBox {
    id: control
    implicitHeight: Style.Theme.controlHeight
    implicitWidth: Math.max(116, contentItem.implicitWidth + 54)
    leftPadding: 14; rightPadding: 34
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    font.pixelSize: Style.Theme.bodySize
    contentItem: Text {
        text: control.displayText; font: control.font; color: Style.Theme.text
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    indicator: Text { text: "⌄"; color: Style.Theme.muted; font.pixelSize: 18; x: control.width - 26; y: (control.height - height) / 2 - 2 }
    background: Rectangle {
        radius: Style.Theme.controlRadius; color: control.hovered ? Style.Theme.hover : Style.Theme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Style.Theme.accentText : Style.Theme.controlBorder
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(control, 130) } }
    }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: control.width - 12; height: 36
        highlighted: control.highlightedIndex === index
        contentItem: Text { text: modelData; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { radius: Style.Theme.controlRadius; color: parent.highlighted ? Style.Theme.selection : "transparent" }
    }
    popup: Popup {
        y: control.height + 6; width: control.width
        padding: 6
        implicitHeight: Math.min(240, list.contentHeight + 12)
        background: Rectangle { radius: 10; color: Style.Theme.surface; border.color: Style.Theme.border }
        contentItem: ListView {
            id: list
            clip: true; implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
