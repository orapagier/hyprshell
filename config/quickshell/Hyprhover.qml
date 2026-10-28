pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import "SettingsModel.js" as Settings

// One controller per output: visibility follows that output's workspace.
PanelWindow {
    id: hover
    property bool available: false
    property var workspace: null
    property var settings: ({})
    required property var services
    required property var inbox
    property var applicationService: null
    property var statusData: ({})
    property var mediaData: ({})
    property var notificationData: ({})
    property string clockText: ""
    property var trayModel: []
    property url wallpaperSource: ""
    readonly property bool opened: available && drawerState.section.length > 0
    readonly property string group: drawerState.displayedSection || "left"
    readonly property rect revealRect: Qt.rect(group === "left" ? 0 : group === "right" ? width - 24 : width / 2 - 32, 0, group === "center" ? 64 : 24, 12)
    readonly property alias drawerSurface: popover
    readonly property var controls: popover.pageItem?.controls || null
    signal revealed()
    signal settingsRequested()
    function close() { drawerState.close(); entryGrace.stop(); }
    function reveal(side) {
        if (!available) return;
        drawerState.hover(side);
        drawerState.section = side;
        drawerState.pinned = false;
        entryGrace.restart();
        drawerState.retain(true);
        revealed();
    }
    function retain() { drawerState.retain(popover.pointerInside || entryGrace.running); }
    onAvailableChanged: if (!available) close()
    onWorkspaceChanged: close()
    onWidthChanged: close()
    onHeightChanged: close()
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-hyprhover"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        width: hover.available ? (hover.opened ? hover.width : 24) : 0
        height: hover.opened ? hover.height : 12
        Region { x: hover.width / 2 - 32; width: hover.available ? 64 : 0; height: 12 }
        Region { x: hover.width - 24; width: hover.available ? 24 : 0; height: 12 }
    }
    MenuController { id: drawerState; dismissPinnedOnLeave: true }
    Timer { id: entryGrace; interval: 900; onTriggered: hover.retain() }
    MouseArea { anchors.fill: parent; onClicked: hover.close() }
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: hover.close()
        HyprhoverSurface {
            id: popover
            anchors.fill: parent
            opened: hover.opened
            alignment: hover.group
            wallpaperSource: hover.wallpaperSource
            translucency: hover.settings.bar?.popdownTranslucency ?? 0.06
            onHoverChanged: inside => {
                if (inside) entryGrace.stop();
                hover.retain();
            }
            page: Component {
                HyprhoverContent {
                    owner: hover
                    group: hover.group
                    onDismissRequested: hover.close()
                    onSettingsRequested: hover.settingsRequested()
                }
            }
        }
    }
    // Keep the entry regions mapped through opening and closing animations.
    Repeater {
        model: ["left", "center", "right"]
        Item {
            required property string modelData
            x: modelData === "left" ? 0 : modelData === "right" ? hover.width - width : (hover.width - width) / 2
            width: modelData === "center" ? 64 : 24
            height: 12
            enabled: hover.available
            HoverHandler {
                onHoveredChanged: {
                    if (hovered) hover.reveal(parent.modelData);
                    else drawerState.leave(parent.modelData);
                }
            }
        }
    }
}
