import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

ColumnLayout {
    id: row
    required property string title
    property string description: ""
    property bool separator: true
    property bool stackOnNarrow: true
    default property alias controls: trailing.data
    Layout.fillWidth: true
    spacing: 0
    GridLayout {
        id: fields
        Layout.fillWidth: true
        columns: row.stackOnNarrow && width < 460 ? 1 : 2
        columnSpacing: 24
        rowSpacing: 8
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        Layout.topMargin: 8
        Layout.bottomMargin: 14
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: fields.columns === 1 ? fields.width : fields.width * 0.38
            spacing: 3
            Label {
                Layout.fillWidth: true
                text: row.title
                color: Style.SettingsTheme.text
                font.pixelSize: Style.SettingsTheme.bodySize
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.description
                color: Style.SettingsTheme.muted
                font.pixelSize: Style.SettingsTheme.captionSize
                wrapMode: Text.WordWrap
            }
        }
        RowLayout {
            id: trailing
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: fields.columns === 1 ? fields.width : fields.width * 0.62 - fields.columnSpacing
            spacing: 10
        }
    }
    Rectangle {
        visible: row.separator
        Layout.fillWidth: true
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        implicitHeight: 1
        color: Style.SettingsTheme.divider
    }
}
