pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var settings
    signal edited(string key, var value)
    spacing: 16
    SettingsCard {
        Layout.fillWidth: true
        title: "Mouse & touchpad"
        subtitle: "These preferences apply to all devices. Individual device configuration may take priority."
        SettingsSlider {
            objectName: "pointerSpeedControl"
            Layout.fillWidth: true
            label: "Pointer speed"
            description: "Lower values slow the pointer; higher values speed it up. Zero keeps normal speed."
            settingValue: root.settings.pointerSpeed
            from: -1; to: 1; stepSize: 0.05
            onEdited: value => root.edited("pointerSpeed", value)
        }
        Repeater {
            model: [
                {key: "mouseNaturalScroll", label: "Mouse natural scrolling"},
                {key: "touchpadNaturalScroll", label: "Touchpad natural scrolling"},
                {key: "tapToClick", label: "Tap touchpad to click"},
                {key: "disableWhileTyping", label: "Disable touchpad while typing"}
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Label { text: parent.modelData.label; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Style.Theme.text }
                SettingsComboBox {
                    objectName: parent.modelData.key + "Control"
                    model: ["Use config", "Enabled", "Disabled"]
                    currentIndex: root.settings[parent.modelData.key] === undefined ? 0 : root.settings[parent.modelData.key] ? 1 : 2
                    onActivated: index => root.edited(parent.modelData.key, index === 0 ? "" : index === 1)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Keyboard layouts"
        subtitle: "Choose a common layout or enter up to four layout codes, such as us,gb or us,ru. Configured layout variants are preserved."
        SettingsComboBox {
            id: layouts
            objectName: "keyboardLayoutsControl"
            Layout.fillWidth: true
            property var codes: ["", "us", "gb", "de", "fr", "es", "us,ru", "us,de", "us,fr"]
            model: ["Use config", "English (US)", "English (UK)", "German", "French", "Spanish", "English (US) + Russian", "English (US) + German", "English (US) + French", "Custom layouts"]
            currentIndex: root.settings.keyboardLayouts === undefined ? 0 : codes.indexOf(root.settings.keyboardLayouts) >= 0 ? codes.indexOf(root.settings.keyboardLayouts) : 9
            onActivated: index => { if (index < codes.length) root.edited("keyboardLayouts", codes[index]); else customLayouts.forceActiveFocus(); }
        }
        SettingsTextField {
            id: customLayouts
            objectName: "customLayouts"
            Layout.fillWidth: true
            text: root.settings.keyboardLayouts || ""
            placeholderText: "Custom layout codes (for example us,gb)"
            maximumLength: 100
            Accessible.name: "Custom keyboard layout codes"
            onTextEdited: root.edited("keyboardLayouts", text.trim())
        }
        Label { text: "Switch between layouts"; color: Style.Theme.text }
        SettingsComboBox {
            id: switching
            objectName: "layoutSwitchControl"
            Layout.fillWidth: true
            property var codes: ["", "grp:alt_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle"]
            model: ["Use config", "Alt + Shift", "Super + Space", "Caps Lock"]
            currentIndex: Math.max(0, codes.indexOf(root.settings.layoutSwitch || ""))
            onActivated: index => root.edited("layoutSwitch", codes[index])
        }
        Label {
            Layout.fillWidth: true
            text: "Switching needs more than one layout. This choice replaces configured keyboard options; Use config restores them. Custom variants remain in your input configuration."
            wrapMode: Text.WordWrap; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize
        }
        SettingsTextField {
            objectName: "typingTest"
            Layout.fillWidth: true
            placeholderText: "Type here to test your layout and key repeat"
            Accessible.name: "Test keyboard settings"
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Key repeat"
        SettingsSlider {
            objectName: "repeatRateControl"
            Layout.fillWidth: true
            label: "Repeat speed"
            settingValue: root.settings.repeatRate
            defaultValue: 25; from: 1; to: 100; suffix: " /s"
            onEdited: value => root.edited("repeatRate", value)
        }
        SettingsSlider {
            objectName: "repeatDelayControl"
            Layout.fillWidth: true
            label: "Delay before repeating"
            settingValue: root.settings.repeatDelay
            defaultValue: 600; from: 100; to: 2000; stepSize: 50; suffix: " ms"
            onEdited: value => root.edited("repeatDelay", value)
        }
    }
    Label {
        Layout.fillWidth: true
        text: "Use config and ↺ restore your existing input configuration. Suggested slider positions are not measured device settings."
        color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; wrapMode: Text.WordWrap
    }
}
