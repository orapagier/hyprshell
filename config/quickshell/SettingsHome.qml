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
    spacing: 20
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        Label {
            text: "YOUR SPACE"
            color: Style.SettingsTheme.accentText
            font.pixelSize: Style.SettingsTheme.captionSize; font.letterSpacing: 2; font.weight: Font.Medium
        }
        Label {
            Layout.fillWidth: true
            text: "Your desktop, your way."
            color: Style.SettingsTheme.text
            font.pixelSize: Math.round(34 * Style.SettingsTheme.textScale); font.weight: Font.DemiBold
            font.letterSpacing: -0.8; wrapMode: Text.WordWrap
        }
        Label {
            Layout.fillWidth: true
            text: "A few small changes. A space that feels like you."
            color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.bodySize
            wrapMode: Text.WordWrap
        }
    }
    SettingsButton {
        objectName: "settingsHomeSearch"
        text: "Find a setting   ·   Ctrl F"
        flat: true
        leftPadding: 0
        onClicked: home.searchRequested()
    }
    GridLayout {
        id: essentials
        Layout.fillWidth: true
        columns: width >= 540 ? 2 : 1
        columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: [
                {section: -8, title: "Appearance", symbol: "󰔎", description: "Colors, fonts & cursor"},
                {section: -1, title: "Hyprpane", symbol: "󰕮", description: "Your panel, down to the details"},
                {section: -7, title: "Displays", symbol: "󰍹", description: "A comfortable view on every screen"},
                {section: -12, title: "Sound", symbol: "󰕾", description: "Speakers, microphone & apps"},
                {section: -15, title: "Network", symbol: "󰤨", description: "Wi-Fi, Ethernet & connections"},
                {section: -25, title: "Bluetooth", symbol: "󰂯", description: "Pair devices & stay connected"}
            ]
            delegate: SettingsTile {
                required property var modelData
                objectName: "settingsHomePage" + modelData.section
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                text: modelData.title; symbol: modelData.symbol; description: modelData.description
                onClicked: home.navigate(modelData.section)
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.SettingsTheme.separator }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        SettingsNavButton {
            objectName: "settingsHomeGuide"
            Layout.fillWidth: true
            text: home.firstRunPending ? "Set up your desktop" : "Help & getting started"
            symbol: "󰋖"
            onClicked: home.navigate(-18)
        }
        SettingsNavButton {
            objectName: "settingsHomePage-23"
            Layout.fillWidth: true
            text: "Keep a backup of your setup"
            symbol: "󰁯"
            onClicked: home.navigate(-23)
        }
    }
}
