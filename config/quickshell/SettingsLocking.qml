import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var settings
    property bool saved: true
    property string runtimeError: ""
    signal lockRequested()
    signal edited(string key, var value)
    spacing: 20
    SettingsCard {
        Layout.fillWidth: true
        title: "Your lock screen"
        subtitle: "Use Hyprlock or another installed Wayland locker. Its own configuration controls the lock screen appearance."
        SettingField {
            Layout.fillWidth: true
            label: "Lock command"
            value: page.settings.command
            hint: "hyprlock"
            description: "Executable and arguments, for example: hyprlock --config /home/you/lock.conf. Quote paths containing spaces. Shell expressions and variables are not expanded. Use a foreground locker."
            onEdited: value => page.edited("command", value)
        }
        SettingsButton {
            objectName: "lockNowButton"
            text: "Lock now"
            enabled: page.saved
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
