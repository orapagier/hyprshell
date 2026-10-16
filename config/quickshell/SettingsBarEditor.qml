pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import "SettingsModel.js" as Model
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var settings
    property var dockSettings: null
    property var taskbarSettings: null
    property var paneItems: []
    signal taskbarEdited(string key, var value)
    signal dockEdited(string key, var value)
    property int currentWorkspace: 1
    property int selectedWorkspace: currentWorkspace >= 1 && currentWorkspace <= 99 ? currentWorkspace : 1
    signal visibilityEdited(var bar)
    signal edited(string key, var value)
    spacing: 16
    SettingsCard {
        Layout.fillWidth: true
        title: "Desktop panels"
        subtitle: "Hyprpane is your status and menu panel. Hyprdock holds apps; Hyprbar is the classic window taskbar. Configure app panels below."
        Label {
            Layout.fillWidth: true
            text: "Use one or two components per monitor and workspace, on different screen edges. A conflicting choice is rejected; choose another edge or disable a component."
            wrapMode: Text.WordWrap
            color: Style.Theme.text
            font.pixelSize: Style.Theme.bodySize
        }
        Label {
            Layout.fillWidth: true
            text: "Top and Bottom own adjacent corners; Left and Right fit between them. App pins are shared by default, with an optional separate list for Hyprdock and Hyprbar. Alt+T continues to target Hyprpane."
            wrapMode: Text.WordWrap
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
        }
    }
    SettingsTaskbarEditor {
        Layout.fillWidth:true
        visible:root.taskbarSettings !== null
        settings:root.taskbarSettings || {}
        paneItems:root.paneItems
        onEdited:(key,value) => root.taskbarEdited(key,value)
    }
    SettingsDockEditor {
        Layout.fillWidth: true
        visible: root.dockSettings !== null
        settings: root.dockSettings || {}
        onEdited: (key, value) => root.dockEdited(key, value)
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Hyprpane visibility"
        subtitle: "Alt+T toggles only the current workspace. Use these buttons to show or hide Hyprpane on all workspaces and clear individual choices."
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            SettingsButton {
                objectName: "barShowAllControl"
                Layout.fillWidth: true
                text: "Show on all"
                onClicked: root.visibilityEdited(Model.withAllBarVisibility(root.settings, true))
            }
            SettingsButton {
                objectName: "barHideAllControl"
                Layout.fillWidth: true
                text: "Hide on all"
                onClicked: root.visibilityEdited(Model.withAllBarVisibility(root.settings, false))
            }
        }
        Label {
            Layout.fillWidth: true
            text: "Individual workspace"
            color: Style.Theme.text
            font.pixelSize: Style.Theme.bodySize
        }
        SettingsComboBox {
            objectName: "barWorkspaceControl"
            Layout.fillWidth: true
            model: Array.from({length: 99}, (_, i) => "Workspace " + (i + 1))
            currentIndex: root.selectedWorkspace - 1
            onActivated: index => root.selectedWorkspace = index + 1
        }
        SettingsSwitch {
            objectName: "barWorkspaceVisibleControl"
            Layout.fillWidth: true
            text: "Show Hyprpane on workspace " + root.selectedWorkspace
            checked: Model.barVisible(root.settings, root.selectedWorkspace)
            onToggled: root.visibilityEdited(Model.withWorkspaceVisibility(root.settings, root.selectedWorkspace, checked))
        }
        Label {
            Layout.fillWidth: true
            text: {
                let choices = Object.keys(root.settings.workspaceOverrides || {}).sort((a, b) => Number(a) - Number(b));
                let baseline = root.settings.visible === false ? "Hidden by default." :
                    root.settings.workspaceScope === "selected" ? "Shown by default on workspaces " + (root.settings.workspaceList || []).join(", ") + "." : "Shown by default on all workspaces.";
                return baseline + (choices.length ? " Individual choices: " + choices.map(w => w + (root.settings.workspaceOverrides[w] ? " on" : " off")).join(", ") + "." : "");
            }
            wrapMode: Text.WordWrap
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Popdown glass"
        subtitle: "Keep a dense glass finish. Higher translucency reveals more of the background; text stays fully visible. Also applies to Super+K."
        SettingsSlider {
            Layout.fillWidth: true
            objectName: "popdownTranslucencyControl"
            label: "Popdown translucency"
            settingValue: (root.settings.popdownTranslucency ?? 0.06) * 100
            suffix: "%"
            resetDescription: "Restore subtle glass (6%)"
            onEdited: value => root.edited("popdownTranslucency", value === "" ? 0.06 : value / 100)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Layout & spacing"
        subtitle: "Set the global gap here. Select a module in the sidebar or preview to adjust its individual spacing."
        Label { text: "Screen edge"; color: Style.Theme.muted; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox {
            objectName: "barPositionControl"
            Layout.fillWidth: true
            model: ["Top", "Left", "Right", "Bottom"]
            currentIndex: Math.max(0, ["top", "left", "right", "bottom"].indexOf(root.settings.position || "top"))
            onActivated: index => root.edited("position", ["top", "left", "right", "bottom"][index])
        }
        Label {
            Layout.fillWidth: true
            text: "On either side edge, the left group sits at the top and the right group sits at the bottom."
            wrapMode: Text.WordWrap; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize
        }
        Label {
            visible: ["left", "right"].includes(root.settings.position)
            text: "Side panel length"; color: Style.Theme.muted; font.pixelSize: Style.Theme.bodySize
        }
        SettingsComboBox {
            objectName: "verticalPresentationControl"
            visible: ["left", "right"].includes(root.settings.position)
            Layout.fillWidth: true
            model: ["Full edge", "Compact"]
            currentIndex: root.settings.verticalPresentation === "compact" ? 1 : 0
            onActivated: index => root.edited("verticalPresentation", index ? "compact" : "edge")
        }
        Label {
            visible: ["left", "right"].includes(root.settings.position)
            Layout.fillWidth: true
            text: "Side panels show icons in circular pills. Compact keeps the groups together. Long panels scroll; hover an icon for its details."
            wrapMode: Text.WordWrap; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [
                    {key: "height", label: "Hyprpane thickness", min: 28, max: 80, fallback: 32},
                    {key: "groupSpacing", label: "Inside shared pills", min: 0, max: 30, fallback: 3},
                    {key: "spacing", label: "Between items / pills", min: 0, max: 30, fallback: 3},
                    {key: "marginTop", label: "Edge margin", min: 0, max: 100, fallback: 5},
                    {key: "paddingBottom", label: "Gap toward windows", min: 0, max: 100, fallback: 0},
                    {key: "marginSide", label: "End margins", min: 0, max: 200, fallback: 10}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    settingValue: root.settings[modelData.key]
                    from: modelData.min; to: modelData.max; suffix: " px"
                    resetDescription: "Restore default " + modelData.label.toLowerCase()
                    onEdited: value => root.edited(modelData.key, value === "" ? modelData.fallback : value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Default appearance"
        subtitle: "Choose a shared style. Individual items can override these settings."
        SettingsSwitch {
            Layout.fillWidth: true
            text: "Adapt colors to wallpaper"
            checked: root.settings.adaptiveColors
            onToggled: root.edited("adaptiveColors", checked)
        }
        SettingsSwitch {
            objectName: "randomVibrantColorsControl"
            Layout.fillWidth: true
            text: "Random vibrant item colors"
            checked: root.settings.randomVibrantColors === true
            onToggled: root.edited("randomVibrantColors", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Give each item a bright color. Colors reshuffle when the wallpaper changes and stay readable. Turn off to use the current theme. Individual colors and wallpaper choices take priority."
            wrapMode: Text.WordWrap
            color: Style.Theme.muted
            font.pixelSize: Style.Theme.captionSize
        }
        SettingsBackgroundControl {
            Layout.fillWidth: true
            switchText: "Show background pills"
            mode: root.settings.background || "inherit"
            inheritLabel: "Use originals"
            inheritDescription: "Original backgrounds · the launcher and settings icons have no pill."
            onEdited: mode => root.edited("background", mode)
        }
        SettingsBackgroundControl {
            objectName: "sharedBackgroundControl"
            Layout.fillWidth: true
            switchText: "Show shared (common) pills"
            mode: root.settings.sharedBackground || "inherit"
            inheritedVisible: root.settings.background !== "off"
            inheritLabel: "Follow background pills"
            inheritDescription: "Shared pills follow the background switch above. Modules keep their grouping and spacing when the pill is hidden."
            onEdited: mode => root.edited("sharedBackground", mode)
        }
        SettingsIconSize {
            Layout.fillWidth: true
            settingValue: root.settings.iconSize
            onEdited: value => root.edited("iconSize", value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Clock & date"
        subtitle: "Choose how the time and date appear on Hyprpane."
        SettingField {
            Layout.fillWidth: true
            label: "Clock format"
            hint: "MMM dd   hh:mm AP   ddd"
            description: "Qt date format · hh:mm for time, ddd for weekday, MMM dd for date."
            value: root.settings.clockFormat
            onEdited: value => root.edited("clockFormat", value)
        }
        Label {
            Layout.fillWidth: true
            text: "Preview   " + Qt.formatDateTime(new Date(), root.settings.clockFormat)
            color: Style.Theme.accentText
            font.pixelSize: Style.Theme.bodySize
            wrapMode: Text.Wrap
        }
    }
}
