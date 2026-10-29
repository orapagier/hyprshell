pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import "SettingsModel.js" as Model
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    objectName: "hyprpaneSettingsEditor"
    required property var settings
    property var fullConfig: null
    property var itemPages: []
    signal itemChosen(int section)
    signal layoutChosen(var config)
    property int currentWorkspace: 1
    property int selectedWorkspace: currentWorkspace >= 1 && currentWorkspace <= 99 ? currentWorkspace : 1
    property int hoverWorkspace: selectedWorkspace
    signal visibilityEdited(var bar)
    signal edited(string key, var value)
    spacing: 16
    property string category: "layout"
    property string searchQuery: ""
    readonly property bool searching: searchQuery.trim().length > 0
    function showCategory(name) { return searching || category === "all" || category === name; }

    Label {
        Layout.fillWidth: true
        text: "Browse Hyprpane settings"
        color: Style.SettingsTheme.text
        font.pixelSize: Style.SettingsTheme.sectionSize
        font.weight: Font.DemiBold
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                {key: "layout", label: "Layout & visibility"},
                {key: "spacing", label: "Items & spacing"},
                {key: "appearance", label: "Appearance"},
                {key: "menus", label: "Menus & clock"},
                {key: "all", label: "All settings"}
            ]
            delegate: SettingsButton {
                required property var modelData
                objectName: "hyprpaneCategory_" + modelData.key
                text: modelData.label
                highlighted: root.category === modelData.key && !root.searching
                enabled: !root.searching
                Accessible.description: "Show " + modelData.label.toLowerCase() + " settings"
                onClicked: root.category = modelData.key
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: root.searching ? "Searching across all Hyprpane categories. Clear search to return to your category."
            : root.category === "layout" ? "Choose panel placement, its background, autohide, and workspace visibility."
            : root.category === "spacing" ? "Arrange items and adjust their size, gaps, margins, and padding. Click an item in the preview to customize it."
            : root.category === "appearance" ? "Choose colors, individual and shared backgrounds, and Hyprknots."
            : root.category === "menus" ? "Adjust hover behavior, menu glass, and the clock format."
            : "All Hyprpane controls, grouped by purpose."
        wrapMode: Text.WordWrap
        color: Style.SettingsTheme.muted
        font.pixelSize: Style.SettingsTheme.captionSize
    }
    SettingsPanelLayout {
        Layout.fillWidth: true
        visible: root.showCategory("layout") && root.fullConfig !== null
        config: root.fullConfig || {bar:root.settings,panels:{}}
        currentWorkspace: root.currentWorkspace
        onLayoutChosen: config => root.layoutChosen(config)
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("layout")
        title: "Position & size"
        subtitle: "Choose the screen edge and panel dimensions."
        Label { text: "Screen edge"; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.bodySize }
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
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        Label {
            visible: ["left", "right"].includes(root.settings.position)
            text: "Side panel length"; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.bodySize
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
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsSlider {
            objectName: "heightControl"
            Layout.fillWidth: true
            label: "Hyprpane thickness"
            settingValue: root.settings.height ?? 32
            from: 28; to: 80; suffix: " px"
            editInterval: 32
            resetDescription: "Restore default Hyprpane thickness"
            onEdited: value => root.edited("height", value === "" ? 32 : value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("layout")
        title: "Panel background & autohide"
        subtitle: "The full pill enables screen-edge attachment; attachment enables autohide."
        SettingsSwitch {
            objectName: "hyprdockControl"
            Layout.fillWidth: true
            text: "Use Hyprdock"
            checked: root.settings.dockEnabled === true
            onToggled: root.edited("dockEnabled", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "A compact clock attached to this edge. Hover its base to reveal items; menus and Settings expand inside the dock. Your ordinary Hyprpane layout is retained."
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsBackgroundControl {
            objectName: "fullBackgroundControl"
            Layout.fillWidth: true
            switchText: "Show full Hyprpane pill"
            mode: root.settings.fullBackground || "off"
            inheritedVisible: root.settings.background !== "off"
            inheritLabel: "Follow background pills"
            inheritDescription: "One pill behind all visible items, from the first to the last. Uses the first visible item's style. Individual and shared pills keep their settings."
            onEdited: mode => root.edited("fullBackground", mode)
        }
        SettingsSlider {
            objectName: "fullPillTransparencyControl"
            Layout.fillWidth: true
            label: "Full pill transparency"
            description: "Fade the background behind the whole panel independently of the other pills. 0% is opaque; 100% is transparent. Overrides item background opacity until reset."
            settingValue: root.settings.fullPillTransparency >= 0 ? root.settings.fullPillTransparency : undefined
            from: 0; to: 100; suffix: "%"
            editInterval: 32
            inheritedText: "Use item styles"
            resetDescription: "Restore original item background styles"
            onEdited: value => root.edited("fullPillTransparency", value === "" ? -1 : value)
        }
        SettingsSwitch {
            objectName: "edgeAttachedControl"
            Layout.fillWidth: true
            text: "Attach to screen edge"
            enabled: Model.fullBackgroundEnabled(root.settings)
            checked: root.settings.edgeAttached === true
            onToggled: root.edited("edgeAttached", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Join the full background pill to the screen with curved feet. Requires the full pill to be on; turning it off also disables attachment and autohide. Edge and end margins apply while detached."
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsSwitch {
            objectName: "autoHideControl"
            Layout.fillWidth: true
            text: "Autohide attached Hyprpane"
            enabled: Model.edgeAttachmentEnabled(root.settings)
            checked: root.settings.autoHide === true
            onToggled: root.edited("autoHide", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Hover the screen edge to reveal Hyprpane with a jelly bounce. Open menus keep it visible. Windows can use the space while autohide is enabled."
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("layout")
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
            color: Style.SettingsTheme.text
            font.pixelSize: Style.SettingsTheme.bodySize
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
            color: Style.SettingsTheme.muted
            font.pixelSize: Style.SettingsTheme.captionSize
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("spacing") && root.itemPages.length > 0
        title: "Individual items"
        subtitle: "Choose an item to edit its visibility, order, shared pill, spacing, colors, and menu style. Hidden items can be customized here too."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 3 : 2
            uniformCellWidths: true
            columnSpacing: 8; rowSpacing: 8
            Repeater {
                model: root.itemPages
                delegate: SettingsButton {
                    required property var modelData
                    objectName: "hyprpaneItem_" + modelData.section
                    Layout.fillWidth: true
                    text: modelData.title
                    onClicked: root.itemChosen(modelData.section)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("spacing")
        title: "Item layout & size"
        subtitle: "Set alignment and shared sizing. Individual items retain their saved overrides."
        SettingsSwitch {
            objectName: "uniformItemsControl"
            Layout.fillWidth: true
            text: "Uniform icon size & spacing"
            checked: root.settings.uniformItems === true
            onToggled: root.edited("uniformItems", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Align the visible tops and bottoms of icons and text to the general icon size, with equal padding and the active item gap. Workspace pills match that height while their numbers stay small. Individual icon and text sizes take priority. Switch off to restore individual padding and spacing."
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsSwitch {
            objectName: "centerItemsControl"
            Layout.fillWidth: true
            text: "Center all items"
            checked: root.settings.centerItems === true
            onToggled: root.edited("centerItems", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Show icons only and place the left, center, and right groups together at the screen’s center. The calendar icon opens the date and time. Item order and shared pills stay the same."
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsIconSize {
            Layout.fillWidth: true
            settingValue: root.settings.iconSize
            inheritedSize: Math.round((root.settings.height || 32) * 0.48)
            onEdited: value => root.edited("iconSize", value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("spacing")
        title: "Item gaps"
        subtitle: "Adjust the gaps inside shared pills and between items. The active gap depends on Hyprknots; uniform spacing takes priority over individual adjustments."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [
                    {key: "groupSpacing", label: "Inside shared pills", min: 0, max: 30, fallback: 3},
                    {key: "spacing", label: "Between items / pills with Hyprknots", min: 0, max: 30, fallback: 3},
                    {key: "compactSpacing", label: "Between items / pills without Hyprknots", min: 0, max: 30, fallback: 3}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    editInterval: 32
                    enabled: modelData.key === "spacing" ? root.settings.hyprknots !== false
                        : modelData.key === "compactSpacing" ? root.settings.hyprknots === false
                        : modelData.key === "groupSpacing" ? root.settings.centerItems !== true && root.settings.uniformItems !== true : true
                    settingValue: root.settings[modelData.key] ?? modelData.fallback
                    from: modelData.min; to: modelData.max; suffix: " px"
                    resetDescription: "Restore default " + modelData.label.toLowerCase()
                    onEdited: value => root.edited(modelData.key, value === "" ? modelData.fallback : value)
                }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("spacing")
        title: "Outer margins"
        subtitle: "Space around Hyprpane. The side facing windows adds a gap toward windows. Reset a side to follow Edge margin and End margins."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28
            rowSpacing: 20
            Repeater {
                model: [
                    {key: "marginTop", label: "Edge margin", min: 0, max: 100, fallback: 5},
                    {key: "paddingBottom", label: "Gap toward windows", min: 0, max: 100, fallback: 0},
                    {key: "marginSide", label: "End margins", min: 0, max: 200, fallback: 10}
                ]
                delegate: SettingsSlider {
                    required property var modelData
                    objectName: modelData.key + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    editInterval: 32
                    settingValue: root.settings[modelData.key] ?? modelData.fallback
                    from: modelData.min; to: modelData.max; suffix: " px"
                    resetDescription: "Restore default " + modelData.label.toLowerCase()
                    onEdited: value => root.edited(modelData.key, value === "" ? modelData.fallback : value)
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28; rowSpacing: 20
            Repeater {
                model: [{side:"Top", label:"Top margin"}, {side:"Bottom", label:"Bottom margin"},
                    {side:"Left", label:"Left margin"}, {side:"Right", label:"Right margin"}]
                delegate: SettingsSlider {
                    required property var modelData
                    readonly property string settingKey: "screenMargin" + modelData.side
                    objectName: settingKey + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    editInterval: 32
                    settingValue: root.settings[settingKey] ?? undefined
                    defaultValue: Model.screenMargins(root.settings)[modelData.side.toLowerCase()]
                    inheritedText: "Follow layout (" + defaultValue + " px)"
                    resetDescription: "Follow Edge margin and End margins"
                    from: 0; to: 200; suffix: " px"
                    onEdited: value => root.edited(settingKey, value === "" ? null : value)
                }
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("spacing")
        title: "Inner padding"
        subtitle: "Extra space around the items, in addition to Full Pill’s 5 px end insets and 20% cross-axis margins. Items have 5 px base padding. Equal left/right values keep the center group centered."
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 600 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 28; rowSpacing: 20
            Repeater {
                model: [{side:"Top", label:"Top padding"}, {side:"Bottom", label:"Bottom padding"},
                    {side:"Left", label:"Left padding"}, {side:"Right", label:"Right padding"}]
                delegate: SettingsSlider {
                    required property var modelData
                    readonly property string settingKey: "contentPadding" + modelData.side
                    objectName: settingKey + "Control"
                    Layout.fillWidth: true
                    label: modelData.label
                    editInterval: 32
                    settingValue: root.settings[settingKey] ?? 0
                    from: 0; to: 100; suffix: " px"
                    resetDescription: "Remove this side's inner padding"
                    onEdited: value => root.edited(settingKey, value === "" ? 0 : value)
                }
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("appearance")
        title: "Colors"
        subtitle: "Choose a shared color style. Individual items can override these settings."
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
            color: Style.SettingsTheme.muted
            font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("appearance")
        title: "Item & shared backgrounds"
        subtitle: "Keep visibility and transparency controls together for each type of pill."
        SettingsBackgroundControl {
            Layout.fillWidth: true
            switchText: "Show background pills"
            mode: root.settings.background || "inherit"
            inheritLabel: "Use originals"
            inheritDescription: "Original backgrounds · the launcher and settings icons have no pill."
            onEdited: mode => root.edited("background", mode)
        }
        SettingsSlider {
            objectName: "individualPillTransparencyControl"
            Layout.fillWidth: true
            label: "Individual pill transparency"
            description: "Fade individual pill backgrounds while keeping icons and text visible. 0% is opaque; 100% is transparent. Overrides item background opacity until reset."
            settingValue: root.settings.individualPillTransparency >= 0 ? root.settings.individualPillTransparency : undefined
            from: 0; to: 100; suffix: "%"
            editInterval: 32
            inheritedText: "Use item styles"
            resetDescription: "Restore original item background styles"
            onEdited: value => root.edited("individualPillTransparency", value === "" ? -1 : value)
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
        SettingsSlider {
            objectName: "groupPillTransparencyControl"
            Layout.fillWidth: true
            label: "Group pill transparency"
            description: "Fade shared pill backgrounds, including grouped circles on side panels. 0% is opaque; 100% is transparent. Overrides item background opacity until reset."
            settingValue: root.settings.groupPillTransparency >= 0 ? root.settings.groupPillTransparency : undefined
            from: 0; to: 100; suffix: "%"
            editInterval: 32
            inheritedText: "Use item styles"
            resetDescription: "Restore original item background styles"
            onEdited: value => root.edited("groupPillTransparency", value === "" ? -1 : value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("appearance")
        title: "Hyprknots"
        subtitle: "Decorative connectors between panel items."
        SettingsSwitch {
            objectName: "hyprknotsControl"
            Layout.fillWidth: true
            text: "Enable Hyprknots"
            checked: root.settings.hyprknots !== false
            onToggled: root.edited("hyprknots", checked)
        }
        Label {
            Layout.fillWidth: true
            text: "Connect Hyprpane items with a line and decorative knots."
            wrapMode: Text.WordWrap
            color: Style.SettingsTheme.muted
            font.pixelSize: Style.SettingsTheme.captionSize
        }
        SettingsSlider {
            objectName: "hyprknotsLineWidthControl"
            Layout.fillWidth: true
            enabled: root.settings.hyprknots !== false
            label: "Hyprknots line thickness"
            settingValue: root.settings.hyprknotsLineWidth ?? 1.8
            from: 0.5; to: 6; stepSize: 0.1; suffix: " px"
            resetDescription: "Restore original line thickness"
            onEdited: value => root.edited("hyprknotsLineWidth", value === "" ? 1.8 : value)
        }
        SettingsSlider {
            objectName: "hyprknotsKnotSizeControl"
            Layout.fillWidth: true
            enabled: root.settings.hyprknots !== false
            label: "Hyprknots knot size"
            description: "Large knots fit within the available gap between items."
            settingValue: root.settings.hyprknotsKnotSize ?? 100
            from: 50; to: 200; stepSize: 5; suffix: "%"
            resetDescription: "Restore original knot size"
            onEdited: value => root.edited("hyprknotsKnotSize", value === "" ? 100 : value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("menus")
        title: "Hover popdowns"
        subtitle: "Choose where hovering opens menus and previews in Hyprpane. When disabled, click to open. Click a workspace number for its preview, then click the preview to switch there. Right-clicking the number also switches directly."
        SettingsSwitch {
            objectName: "hoverPopdownsDefaultControl"
            Layout.fillWidth: true
            text: "Enable hover popdowns by default"
            checked: root.settings.hoverPopdowns !== false
            onToggled: root.edited("hoverPopdowns", checked)
        }
        SettingsComboBox {
            objectName: "hoverPopdownWorkspaceControl"
            Layout.fillWidth: true
            model: Array.from({length: 99}, (_, i) => "Workspace " + (i + 1))
            currentIndex: root.hoverWorkspace - 1
            onActivated: index => root.hoverWorkspace = index + 1
        }
        SettingsSwitch {
            objectName: "hoverPopdownWorkspaceEnabledControl"
            Layout.fillWidth: true
            text: "Enable hover popdowns on workspace " + root.hoverWorkspace
            checked: Model.hoverPopdownsEnabled(root.settings, root.hoverWorkspace)
            onToggled: root.edited("hoverPopdownOverrides", Object.assign({}, root.settings.hoverPopdownOverrides || {}, {[String(root.hoverWorkspace)]: checked}))
        }
        SettingsButton {
            text: "Use default on this workspace"
            onClicked: {
                let next = Object.assign({}, root.settings.hoverPopdownOverrides || {});
                delete next[String(root.hoverWorkspace)];
                root.edited("hoverPopdownOverrides", next);
            }
        }
        Label {
            Layout.fillWidth: true
            text: {
                let choices = root.settings.hoverPopdownOverrides || {};
                let keys = Object.keys(choices).sort((a, b) => Number(a) - Number(b));
                return keys.length ? "Workspace overrides: " + keys.map(w => w + (choices[w] ? " on" : " off")).join(", ") : "All workspaces follow the default.";
            }
            wrapMode: Text.WordWrap
            color: Style.SettingsTheme.muted
            font.pixelSize: Style.SettingsTheme.captionSize
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: root.showCategory("menus")
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
        visible: root.showCategory("menus")
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
            color: Style.SettingsTheme.accentText
            font.pixelSize: Style.SettingsTheme.bodySize
            wrapMode: Text.Wrap
        }
    }

}
