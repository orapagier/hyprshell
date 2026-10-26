import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

ColumnLayout {
    id: page
    required property var settings
    signal edited(string key, var value)
    signal navigate(int section)
    spacing: 16
    SettingsCard {
        title: "Reading and interaction"
        subtitle: "These preferences apply immediately to Settings and save automatically."
        Layout.fillWidth: true
        Label { text: "Settings text size"; color: Style.SettingsTheme.text; font.pixelSize: Style.SettingsTheme.bodySize }
        SettingsComboBox {
            objectName: "accessibleTextSize"
            Layout.fillWidth: true
            model: ["Standard · 100%", "Larger · 115%", "Large · 130%", "Extra large · 150%"]
            currentIndex: [1, 1.15, 1.3, 1.5].indexOf(page.settings.textScale)
            onActivated: index => page.edited("textScale", [1, 1.15, 1.3, 1.5][index])
        }
        SettingsSwitch { objectName: "accessibleContrast"; text: "High contrast in Settings"; checked: page.settings.highContrast; onToggled: page.edited("highContrast", checked); Layout.fillWidth: true }
        SettingsSwitch { objectName: "accessibleMotion"; text: "Reduce desktop motion"; checked: page.settings.reducedMotion; onToggled: page.edited("reducedMotion", checked); Layout.fillWidth: true }
        Label { text: "Reduced motion disables compositor animations and Settings transitions. Turning it off restores the animation choice in Windows. Independent app animations follow each app’s preferences."; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Label { text: "Preview: clear text, visible focus borders, and comfortably sized controls."; color: Style.SettingsTheme.text; font.pixelSize: Style.SettingsTheme.bodySize; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    SettingsCard {
        title: "Application and desktop size"
        subtitle: "Application fonts, cursor size, display scaling, and bar item sizes are controlled separately so you can adjust each for your screen."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { text: "Application font & cursor"; onClicked: page.navigate(-8) }
            SettingsButton { text: "Display scaling"; onClicked: page.navigate(-7) }
            SettingsButton { text: "Bar appearance"; onClicked: page.navigate(-1) }
        }
        Label { text: "Navigate with Tab and Shift+Tab; activate controls with Space or Enter. Ctrl+F focuses Settings search. Super+K opens the shortcut guide."; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
}
