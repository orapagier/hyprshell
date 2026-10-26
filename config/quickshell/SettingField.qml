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
        color: Style.SettingsTheme.text
        font.pixelSize: Style.SettingsTheme.bodySize
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
            color: Style.SettingsTheme.text
            font.pixelSize: Style.SettingsTheme.bodySize
            selectionColor: Style.SettingsTheme.selection
            selectedTextColor: Style.SettingsTheme.text
            text: field.value
            placeholderText: field.hint
            placeholderTextColor: Style.SettingsTheme.muted
            selectByMouse: true
            background: Rectangle {
                radius: 8
                color: Style.SettingsTheme.field
                border.color: Style.SettingsTheme.controlBorder
                Behavior on color {
                    ColorAnimation {
                        duration: Style.SettingsTheme.duration(field, 130)
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
        color: Style.SettingsTheme.muted
        font.pixelSize: Style.SettingsTheme.captionSize
    }
}
