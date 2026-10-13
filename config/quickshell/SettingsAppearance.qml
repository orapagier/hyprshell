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
        title: "Window transparency"
        subtitle: "Let your wallpaper show through. Increase transparency for a lighter desktop."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [
                    {key: "activeOpacity", label: "Focused windows", description: "Keep your current window clear and readable."},
                    {key: "inactiveOpacity", label: "Unfocused windows", description: "Soften windows in the background."}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    description: modelData.description
                    settingValue: root.settings[modelData.key]
                    defaultValue: 0
                    to: 100
                    suffix: "%"
                    inverted: true
                    onEdited: value => root.edited(modelData.key, value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Glass & blur"
        subtitle: "Frost the content behind translucent windows. Add transparency above to make the effect visible."
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Background blur"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; Layout.fillWidth: true }
            SettingsComboBox {
                objectName: "blurMode"
                model: ["Use config", "Enabled", "Disabled"]
                currentIndex: root.settings.blur === undefined ? 0 : root.settings.blur ? 1 : 2
                onActivated: root.edited("blur", currentIndex === 0 ? "" : currentIndex === 1)
            }
        }
        SettingsSlider {
            objectName: "blurSizeControl"
            Layout.fillWidth: true
            enabled: root.settings.blur !== false
            label: "Blur strength"
            description: "A higher value creates a softer, more frosted surface."
            settingValue: root.settings.blurSize
            defaultValue: 8
            from: 1; to: 20; suffix: " px"
            onEdited: value => root.edited("blurSize", value)
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            enabled: root.settings.blur !== false
            SettingsSlider {
                objectName: "blurPassesControl"
                Layout.fillWidth: true
                label: "Blur passes"
                description: "More passes smooth strong blur and use more GPU power."
                settingValue: root.settings.blurPasses
                defaultValue: 2
                from: 1; to: 4
                onEdited: value => root.edited("blurPasses", value)
            }
            SettingsSlider {
                objectName: "blurVibrancyControl"
                Layout.fillWidth: true
                label: "Glass vibrancy"
                description: "Bring out the colors behind the glass."
                settingValue: root.settings.blurVibrancy === undefined ? undefined : root.settings.blurVibrancy * 100
                defaultValue: 20
                suffix: "%"
                onEdited: value => root.edited("blurVibrancy", value === "" ? "" : value / 100)
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Window shape & spacing"
        subtitle: "Adjust each screen edge separately. Unset edges follow All screen edges (10 px unless overridden). The bar reserves its own space."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [
                    {key: "rounding", label: "Corner radius", max: 100, fallback: 10},
                    {key: "borderSize", label: "Border width", max: 20, fallback: 3},
                    {key: "gapsIn", label: "Between windows", max: 100, fallback: 5},
                    {key: "gapsOut", label: "All screen edges", max: 100, fallback: 10},
                    {key: "gapsOutTop", label: "Top edge", max: 100, fallback: root.settings.gapsOut ?? 10},
                    {key: "gapsOutRight", label: "Right edge", max: 100, fallback: root.settings.gapsOut ?? 10},
                    {key: "gapsOutBottom", label: "Bottom edge", max: 100, fallback: root.settings.gapsOut ?? 10},
                    {key: "gapsOutLeft", label: "Left edge", max: 100, fallback: root.settings.gapsOut ?? 10}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    settingValue: root.settings[modelData.key]
                    defaultValue: modelData.fallback
                    to: modelData.max
                    suffix: " px"
                    onEdited: value => root.edited(modelData.key, value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Motion & depth"
        subtitle: "Finish the desktop with movement and separation."
        Repeater {
            model: [{key: "shadows", label: "Window shadows"}, {key: "animations", label: "Animations"}]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Label { text: modelData.label; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; Layout.fillWidth: true }
                SettingsComboBox {
                    model: ["Use config", "Enabled", "Disabled"]
                    currentIndex: root.settings[parent.modelData.key] === undefined ? 0 : root.settings[parent.modelData.key] ? 1 : 2
                    onActivated: root.edited(parent.modelData.key, currentIndex === 0 ? "" : currentIndex === 1)
                }
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: "Use config leaves a setting under your Hyprland configuration. Sliders start at suggested values until you adjust them. Use ↺ to remove an override. App-specific window rules may take priority."
        color: Style.Theme.muted
        font.pixelSize: Style.Theme.captionSize
        wrapMode: Text.WordWrap
    }
}
