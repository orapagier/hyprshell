import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

ColumnLayout {
    id: field
    property string label: ""
    property string value: ""
    property string hint: ""
    property string description: ""
    property bool colorField: false
    signal edited(string value)
    spacing: 8
    Label {
        text: field.label
        color: Style.Theme.text
        font.pixelSize: Style.Theme.bodySize
    }
    RowLayout {
        Layout.fillWidth: true
        Rectangle {
            visible: field.colorField
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 7
            border.color: "#667085"
            color: /^#[0-9a-fA-F]{6}$/.test(field.value) ? field.value : "transparent"
        }
        TextField {
            id: input
            Layout.fillWidth: true
            implicitHeight: 42
            leftPadding: 14
            Accessible.name: field.label
            rightPadding: 14
            color: Style.Theme.text
            font.pixelSize: Style.Theme.bodySize
            selectionColor: Style.Theme.selection
            selectedTextColor: Style.Theme.text
            text: field.value
            placeholderText: field.hint
            placeholderTextColor: Style.Theme.muted
            selectByMouse: true
            background: Rectangle {
                radius: 8
                color: Style.Theme.field
                border.color: input.activeFocus ? Style.Theme.accentText : Style.Theme.controlBorder
                Behavior on color {
                    ColorAnimation {
                        duration: Style.Theme.duration(field, 130)
                    }
                }
            }
            onTextEdited: field.edited(text)
        }
    }
    Label {
        visible: field.description !== ""
        Layout.fillWidth: true
        text: field.description
        wrapMode: Text.WordWrap
        color: Style.Theme.muted
        font.pixelSize: Style.Theme.captionSize
    }
}
