pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var settings
    required property var barSettings
    property var allItems: []
    readonly property var pillGroups: ["Own pill", ...Array.from(new Set(allItems.map(i => i.pillGroup).filter(name => !!name)))]
    property bool saving: false
    signal edited(string key, var value)
    signal moveRequested(int direction)
    signal resetRequested()
    spacing: 16
    SettingsCard {
        Layout.fillWidth: true
        title: "Visibility & position"
        subtitle: "Choose where this item belongs in Hyprpane."
        SettingsSwitch {
            Layout.fillWidth: true
            text: "Show in Hyprpane"
            checked: root.settings.enabled !== false
            onToggled: root.edited("enabled", checked)
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Alignment"; color: Style.Theme.muted; font.pixelSize: Style.Theme.bodySize }
                SettingsComboBox {
                    Layout.fillWidth: true
                    model: ["left", "right"].includes(root.barSettings.position) ? ["Top", "Center", "Bottom"] : ["Left", "Center", "Right"]
                    currentIndex: Math.max(0, ["left", "center", "right"].indexOf(root.settings.side))
                    onActivated: root.edited("side", ["left", "center", "right"][currentIndex])
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Order within group"; color: Style.Theme.muted; font.pixelSize: Style.Theme.bodySize }
                RowLayout {
                    Layout.fillWidth: true
                    SettingsButton { Layout.fillWidth: true; text: "← Earlier"; onClicked: root.moveRequested(-1) }
                    SettingsButton { Layout.fillWidth: true; text: "Later →"; onClicked: root.moveRequested(1) }
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Shared pill"
        subtitle: "Join a named pill or create one, then assign other modules to it. Each module keeps its own actions. The first module supplies the shared background style."
        SettingsComboBox {
            objectName: "pillGroupControl"
            Layout.fillWidth: true
            model: root.pillGroups
            currentIndex: root.settings.pillGroup ? Math.max(0, root.pillGroups.indexOf(root.settings.pillGroup, 1)) : 0
            onActivated: root.edited("pillGroup", currentIndex === 0 ? "" : root.pillGroups[currentIndex])
        }
        SettingField {
            Layout.fillWidth: true
            label: "Pill group name"
            hint: "For example: Connections"
            description: "Use the same name to share a pill. Clear the name to give this module its own pill. Alignment moves the entire pill; dragging to another alignment removes this module from it."
            value: root.settings.pillGroup || ""
            onEdited: value => root.edited("pillGroup", value)
        }
        SettingsBackgroundControl {
            objectName: "sharedBackgroundControl"
            Layout.fillWidth: true
            visible: !!root.settings.pillGroup
            switchText: "Show this shared pill"
            mode: root.settings.sharedBackground || "inherit"
            inheritedVisible: root.barSettings.sharedBackground === "on" || (root.barSettings.sharedBackground !== "off" && root.barSettings.background !== "off")
            inheritDescription: "Following the general shared pill setting. This switch changes the whole named group."
            onEdited: mode => root.edited("sharedBackground", mode)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Item spacing"
        subtitle: root.barSettings.uniformItems === true ? "Uniform spacing is on. Change the active gap in Hyprpane settings, or switch uniform spacing off to use these saved adjustments." : "Negative values reduce the gap; positive values add space. Gaps stop at zero. Base spacing: " + (!root.barSettings.centerItems && root.settings.pillGroup ? (root.barSettings.groupSpacing ?? 3) : root.barSettings.hyprknots === false ? (root.barSettings.compactSpacing ?? 3) : (root.barSettings.spacing ?? 3)) + " px."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [{key: "spacingLeft", label: "Space before adjustment"}, {key: "spacingRight", label: "Space after adjustment"}]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    enabled: root.barSettings.uniformItems !== true
                    Layout.fillWidth: true
                    label: modelData.label
                    settingValue: root.settings[modelData.key] ?? 0
                    from: -200; to: 200; suffix: " px"
                    resetDescription: "Use global spacing"
                    onEdited: value => root.edited(modelData.key, value === "" ? 0 : value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Padding inside pill"
        subtitle: root.barSettings.uniformItems === true ? "Uniform spacing uses equal padding. Switch it off in Hyprpane settings to use these saved padding adjustments." : "Adjust space inside this item's click area, between its content and the pill edges. Positive values add space; negative values reduce the original padding. Works in shared pills too."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [{key:"paddingLeft", label:"Left padding adjustment"}, {key:"paddingRight", label:"Right padding adjustment"}]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    enabled: root.barSettings.uniformItems !== true
                    Layout.fillWidth: true
                    label: modelData.label
                    settingValue: root.settings[modelData.key] ?? 0
                    from: -200; to: 200; suffix: " px"
                    resetDescription: "Restore original padding"
                    onEdited: value => root.edited(modelData.key, value === "" ? 0 : value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Text & icon"
        subtitle: root.settings.id === "tray" ? "Tray artwork is provided by each application. Overrides do not replace it." : "Leave overrides empty to keep the original text and glyph."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [{key: "text", label: "Text or glyph"}, {key: "icon", label: "Icon glyph"}]
                delegate: SettingField {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    value: root.settings[modelData.key] || ""
                    hint: "Use original"
                    onEdited: value => root.edited(modelData.key, value)
                }
            }
            SettingsCheckBox { text: "Hide text"; checked: root.settings.hideText || false; onToggled: root.edited("hideText", checked) }
            SettingsCheckBox { text: "Hide icon"; checked: root.settings.hideIcon || false; onToggled: root.edited("hideIcon", checked) }
        }
        SettingsIconSize {
            Layout.fillWidth: true
            individual: true
            enabled: root.barSettings.uniformItems !== true || root.settings.id === "workspaces"
            settingValue: root.settings.iconSize
            inheritedSize: root.barSettings.iconSize
            onEdited: value => root.edited("iconSize", value)
        }
        SettingsSlider {
            Layout.fillWidth: true
            objectName: "fontSizeControl"
                label: "Text size"
            settingValue: root.settings.fontSize > 0 ? root.settings.fontSize : undefined
            inheritedText: "Follow item size"
            defaultValue: Math.max(8, Math.round(12 * (root.settings.iconSize || root.barSettings.iconSize || 16) / 16))
            from: 1; to: 48; suffix: " px"
            resetDescription: "Follow item size again"
            onEdited: value => root.edited("fontSize", value === "" ? 0 : value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Colors & background"
        subtitle: "Custom colors take priority over wallpaper colors."
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Wallpaper colors"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; Layout.fillWidth: true }
            SettingsComboBox {
                model: ["Use general setting", "Enabled", "Disabled"]
                currentIndex: Math.max(0, ["inherit", "on", "off"].indexOf(root.settings.adaptiveColors))
                onActivated: root.edited("adaptiveColors", ["inherit", "on", "off"][currentIndex])
            }
        }
        SettingsBackgroundControl {
            Layout.fillWidth: true
            visible: !root.settings.pillGroup
            mode: root.settings.background || "inherit"
            inheritedVisible: root.barSettings.background === "on" || (root.barSettings.background !== "off" && root.settings.id !== "launcher" && root.settings.id !== "settings")
            onEdited: mode => root.edited("background", mode)
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [{key: "textColor", label: "Text color"}, {key: "iconColor", label: "Icon color"}, {key: "backgroundColor", label: "Background color"}, {key: "outlineColor", label: "Outline color"}]
                delegate: SettingField {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    value: root.settings[modelData.key] || ""
                    colorField: true
                    hint: "Default · #RRGGBB"
                    onEdited: value => root.edited(modelData.key, value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Shape & transparency"
        subtitle: "Refine the item's surface and overall visibility."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            SettingsSlider {
                Layout.fillWidth: true
                objectName: "opacityControl"
                label: "Item opacity"
                settingValue: (root.settings.opacity ?? 1) * 100
                suffix: "%"
                resetDescription: "Restore full opacity"
                onEdited: value => root.edited("opacity", value === "" ? 1 : value / 100)
            }
            SettingsSlider {
                Layout.fillWidth: true
                objectName: "backgroundOpacityControl"
                label: "Background opacity"
                settingValue: root.settings.backgroundOpacity >= 0 ? root.settings.backgroundOpacity * 100 : undefined
                inheritedText: "Original opacity"
                defaultValue: 80; suffix: "%"
                resetDescription: "Restore original background opacity"
                onEdited: value => root.edited("backgroundOpacity", value === "" ? -1 : value / 100)
            }
            SettingsSlider {
                Layout.fillWidth: true
                objectName: "radiusControl"
                label: "Corner radius"
                settingValue: root.settings.radius >= 0 ? root.settings.radius : undefined
                inheritedText: "Original shape"
                defaultValue: 12; to: 50; suffix: " px"
                resetDescription: "Restore original corner radius"
                onEdited: value => root.edited("radius", value === "" ? -1 : value)
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Popdown glass"
        subtitle: "Keep a dense glass finish. Higher translucency reveals more of the background; text stays fully visible. Reset to follow the general setting."
        SettingsSlider {
            Layout.fillWidth: true
            objectName: "popdownTranslucencyControl"
            label: "Popdown translucency"
            settingValue: root.settings.popdownTranslucency >= 0 ? root.settings.popdownTranslucency * 100 : undefined
            inheritedText: "Use general setting"
            defaultValue: (root.barSettings.popdownTranslucency ?? 0.06) * 100
            suffix: "%"
            resetDescription: "Use general setting"
            onEdited: value => root.edited("popdownTranslucency", value === "" ? -1 : value / 100)
        }
    }
    SettingsButton {
        text: "Restore last saved item"
        enabled: !root.saving
        onClicked: root.resetRequested()
        ToolTip.visible: hovered
        ToolTip.text: "Restore this item's last saved settings and position"
    }
}
