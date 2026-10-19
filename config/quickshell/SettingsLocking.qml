import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var settings
    property bool saved: true
    property string runtimeError: ""
    property string commandDraft: settings.command
    readonly property bool dirty: commandDraft !== settings.command
    signal lockRequested()
    signal edited(string key, var value)
    spacing: 20
    SettingsCard {
        Layout.fillWidth: true
        title: "Your lock screen"
        subtitle: "Hyprlock keeps your apps open behind a desktop snapshot. You can also choose another installed Wayland locker."
        SettingsSlider {
            objectName: "lockBackgroundTransparency"
            Layout.fillWidth: true
            label: "Background transparency"
            description: "Higher values remove more of the dark tint. Blur is controlled separately below. Applies the next time you lock. Available with the default hyprlock command."
            suffix: "%"
            from: 0; to: 100; stepSize: 1
            allowReset: false
            settingValue: page.settings.backgroundTransparency ?? 85
            enabled: page.settings.command.trim() === "hyprlock"
            onEdited: value => page.edited("backgroundTransparency", value)
        }
        SettingsSlider {
            objectName: "lockBlurPasses"
            Layout.fillWidth: true
            label: "Background blur passes"
            description: "0 turns blur off for a clear desktop snapshot. More passes create a stronger glass effect. Applies the next time you lock."
            from: 0; to: 4; stepSize: 1
            allowReset: false
            settingValue: page.settings.blurPasses ?? 2
            enabled: page.settings.command.trim() === "hyprlock"
            onEdited: value => page.edited("blurPasses", value)
        }
        SettingsSlider {
            objectName: "lockBlurSize"
            Layout.fillWidth: true
            label: "Background blur strength"
            description: "Size of each blur pass. Independent of window glass settings; applies the next time you lock."
            from: 1; to: 20; stepSize: 1
            allowReset: false
            settingValue: page.settings.blurSize ?? 8
            enabled: page.settings.command.trim() === "hyprlock" && (page.settings.blurPasses ?? 2) > 0
            onEdited: value => page.edited("blurSize", value)
        }
        SettingField {
            objectName: "lockCommandField"
            Layout.fillWidth: true
            label: "Lock command"
            value: page.commandDraft
            hint: "hyprlock"
            description: "Executable and arguments, for example: hyprlock --config /home/you/lock.conf. Quote paths containing spaces. Shell expressions and variables are not expanded. Use a foreground locker."
            onEdited: value => page.commandDraft = value
        }
        RowLayout {
            SettingsButton { objectName: "applyLockCommand"; text: "Apply lock command"; highlighted: page.dirty; enabled: page.dirty && page.saved && page.commandDraft.trim().length > 0; onClicked: page.edited("command", page.commandDraft) }
            SettingsButton { text: "Discard command edit"; visible: page.dirty; onClicked: page.commandDraft = Qt.binding(() => page.settings.command) }
        }
        SettingsButton {
            objectName: "lockNowButton"
            text: "Lock now"
            enabled: page.saved && !page.dirty
            onClicked: page.lockRequested()
        }
        Label {
            Layout.fillWidth: true
            text: "Save a valid command before testing. Unlock with your locker's configured authentication."
            wrapMode: Text.WordWrap
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Automatic locking"
        subtitle: "Uses Hypridle while Hyprshell is running. Install hypridle and your chosen locker first. Disable any separate hypridle service or autostart before enabling this."
        SettingsCheckBox {
            objectName: "automaticLockSwitch"
            text: "Enable automatic locking"
            checked: page.settings.enabled
            onToggled: page.edited("enabled", checked)
        }
        SettingField {
            Layout.fillWidth: true
            label: "Lock after inactivity (minutes)"
            value: String(page.settings.idleMinutes)
            hint: "5"
            description: "0 disables the idle timeout. Enter a whole number from 0 to 240."
            onEdited: value => page.edited("idleMinutes", /^\d+$/.test(value) ? Number(value) : value)
        }
        SettingsCheckBox {
            objectName: "lockBeforeSleepSwitch"
            text: "Lock before sleep"
            checked: page.settings.beforeSleep
            onToggled: page.edited("beforeSleep", checked)
        }
    }
    Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: page.runtimeError
        wrapMode: Text.WordWrap
        color: Style.Theme.danger
    }
}
