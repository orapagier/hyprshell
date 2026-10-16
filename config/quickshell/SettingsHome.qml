pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

ColumnLayout {
    id: home
    required property var navigation
    property bool firstRunPending: false
    signal navigate(int section)
    signal searchRequested()
    spacing: 22
    Label {
        Layout.fillWidth: true
        text: "Hyprshell Settings"
        color: Style.Theme.text; font.pixelSize: Style.Theme.titleSize; font.bold: true
        wrapMode: Text.WordWrap
    }
    Label {
        Layout.fillWidth: true
        Layout.topMargin: -12
        text: "Choose what you’d like to change, or search for a setting."
        color: Style.Theme.muted; font.pixelSize: Style.Theme.bodySize
        wrapMode: Text.WordWrap
    }
    Flow {
        Layout.fillWidth: true
        spacing: 10
        SettingsButton {
            objectName: "settingsHomeSearch"
            text: "Search settings"; highlighted: true
            onClicked: home.searchRequested()
        }
        SettingsButton {
            objectName: "settingsHomeGuide"
            text: home.firstRunPending ? "Set up your desktop" : "Getting-started guide"
            onClicked: home.navigate(-18)
        }
    }
    GridLayout {
        id: categories
        Layout.fillWidth: true
        columns: width >= 720 ? 3 : 1
        columnSpacing: 16; rowSpacing: 18
        Repeater {
            model: home.navigation
            delegate: SettingsCard {
                id: category
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignTop
                title: modelData.group
                collapsible: false
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 560 ? 2 : 1
                    columnSpacing: 12; rowSpacing: 6
                    Repeater {
                        model: category.modelData.pages
                        delegate: SettingsNavButton {
                            required property var modelData
                            objectName: "settingsHomePage" + modelData.section
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: modelData.title; symbol: modelData.symbol
                            onClicked: home.navigate(modelData.section)
                        }
                    }
                }
            }
        }
    }
}
