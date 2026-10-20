pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import "SettingsModel.js" as Model
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var settings
    property int selectedWorkspace: 1
    signal edited(string key, var value)
    spacing: 16
    SettingsCard {
        Layout.fillWidth: true
        title: "Effect workspaces"
        subtitle: "Choose where window transparency and blur apply. With a workspace selection, other workspaces use full compositor opacity with blur off; app-owned transparency can remain."
        SettingsComboBox {
            objectName: "effectWorkspaceScopeControl"
            Layout.fillWidth: true
            model: ["Use config", "All workspaces", "Selected workspaces"]
            currentIndex: root.settings.effectWorkspaceScope === undefined ? 0 : root.settings.effectWorkspaceScope === "all" ? 1 : 2
            onActivated: root.edited("effectWorkspaceScope", currentIndex === 0 ? "" : currentIndex === 1 ? "all" : "selected")
        }
        SettingsComboBox {
            objectName: "effectWorkspaceControl"
            visible: root.settings.effectWorkspaceScope === "selected"
            Layout.fillWidth: true
            model: Array.from({length: 99}, (_, i) => "Workspace " + (i + 1))
            currentIndex: root.selectedWorkspace - 1
            onActivated: index => root.selectedWorkspace = index + 1
        }
        SettingsSwitch {
            objectName: "effectWorkspaceEnabledControl"
            visible: root.settings.effectWorkspaceScope === "selected"
            Layout.fillWidth: true
            text: "Apply effects on workspace " + root.selectedWorkspace
            checked: (root.settings.effectWorkspaces || []).indexOf(root.selectedWorkspace) >= 0
            onToggled: {
                let list = (root.settings.effectWorkspaces || []).filter(w => w !== root.selectedWorkspace);
                if (checked) list.push(root.selectedWorkspace);
                root.edited("effectWorkspaces", list.sort((a, b) => a - b));
            }
        }
        Label {
            visible: root.settings.effectWorkspaceScope === "selected"
            Layout.fillWidth: true
            text: (root.settings.effectWorkspaces || []).length ? "Selected workspaces: " + root.settings.effectWorkspaces.join(", ") : "No workspaces selected. Effects are off until you select one."
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
            wrapMode: Text.WordWrap
        }
    }
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
                    {key: "inactiveOpacity", label: "Unfocused windows", description: "Soften windows in the background."},
                    {key: "fullscreenOpacity", label: "Fullscreen windows", description: "Control transparency while an app is fullscreen."}
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
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            Label { text: "Background blur"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            SettingsComboBox {
                Layout.fillWidth: true
                objectName: "blurMode"
                model: ["Use config", "Frosted glass", "Clear transparency (no blur)"]
                currentIndex: root.settings.blur === undefined ? 0 : root.settings.blur ? 1 : 2
                onActivated: root.edited("blur", currentIndex === 0 ? "" : currentIndex === 1)
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            Label { text: "Blur applies to"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            SettingsComboBox {
                Layout.fillWidth: true
                objectName: "blurFocusControl"
                enabled: root.settings.blur !== false
                model: ["Use config", "Both window states", "Focused windows only", "Unfocused windows only"]
                currentIndex: root.settings.blurFocus === undefined ? 0 : ["both", "focused", "unfocused"].indexOf(root.settings.blurFocus) + 1
                onActivated: root.edited("blurFocus", currentIndex === 0 ? "" : ["both", "focused", "unfocused"][currentIndex - 1])
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
        title: "Advanced glass & blur"
        subtitle: "These blur parameters are shared across workspaces and window states. Window transparency also fades text and controls. App-owned transparent backgrounds can keep text opaque."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            enabled: root.settings.blur !== false
            Repeater {
                model: [
                    {key: "blurNoise", label: "Glass grain", fallback: 0.0117, max: 1},
                    {key: "blurContrast", label: "Glass contrast", fallback: 0.8916, max: 2},
                    {key: "blurBrightness", label: "Glass brightness", fallback: 0.8172, max: 2},
                    {key: "blurVibrancyDarkness", label: "Vibrancy in dark areas", fallback: 0, max: 1},
                    {key: "blurPopupsIgnoreAlpha", label: "Popup alpha threshold", fallback: 0.2, max: 1},
                    {key: "blurInputMethodsIgnoreAlpha", label: "Input method alpha threshold", fallback: 0.2, max: 1}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    description: modelData.key.indexOf("IgnoreAlpha") >= 0 ? "Skip blur for pixels at or below this opacity." : "Tune the appearance of the blurred background."
                    settingValue: root.settings[modelData.key] === undefined ? undefined : root.settings[modelData.key] * 100
                    defaultValue: modelData.fallback * 100
                    to: modelData.max * 100
                    suffix: "%"
                    onEdited: value => root.edited(modelData.key, value === "" ? "" : value / 100)
                }
            }
        }
        Repeater {
            model: [
                {key: "blurIgnoreOpacity", label: "Keep blur strong through transparent windows"},
                {key: "blurOptimizations", label: "Blur performance optimizations"},
                {key: "blurXray", label: "X-ray glass (blur wallpaper behind tiled windows)"},
                {key: "blurSpecial", label: "Blur behind special workspaces"},
                {key: "blurPopups", label: "Blur application popups"},
                {key: "blurInputMethods", label: "Blur input method popups"}
            ]
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                enabled: root.settings.blur !== false
                Label {
                    Layout.fillWidth: true
                    text: parent.modelData.label
                    color: Style.Theme.text
                    font.pixelSize: Style.Theme.bodySize
                    wrapMode: Text.WordWrap
                }
                SettingsComboBox {
                    objectName: parent.modelData.key + "Control"
                    Layout.fillWidth: true
                    model: ["Use config", "Enabled", "Disabled"]
                    currentIndex: root.settings[parent.modelData.key] === undefined ? 0 : root.settings[parent.modelData.key] ? 1 : 2
                    onActivated: root.edited(parent.modelData.key, currentIndex === 0 ? "" : currentIndex === 1)
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: "Special-workspace and popup blur are compositor-wide options. Focus and numbered-workspace filters apply to normal application windows. Blur passes and special-workspace blur can increase GPU use."
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
            wrapMode: Text.WordWrap
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Window shape & spacing"
        subtitle: "Edge spacing applies to every workspace: tiled, pseudotiled and auto-floating. Unset edges follow All screen edges (10 px by default). Panels reserve their own space; Between windows controls tiled layouts."
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
