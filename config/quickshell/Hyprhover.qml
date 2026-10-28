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
    readonly property var controls: popover.pageItem?.controls || null
    signal revealed()
    signal settingsRequested()
    function close() { drawerState.close(); menuState.close(); entryGrace.stop(); }
    function reveal(side) {
        if (!available) return;
        if (drawerState.section !== side) menuState.close();
        drawerState.hover(side);
        drawerState.section = side;
        drawerState.pinned = false;
        entryGrace.restart();
        drawerState.retain(true);
        revealed();
    }
    function retain() { drawerState.retain(popover.pointerInside || entryGrace.running || menuState.section.length > 0); }
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
    MenuController {
        id: menuState
        hoverEnabled: Settings.hoverPopdownsEnabled(hover.settings.bar || {}, hover.workspace)
        dismissPinnedOnLeave: !dropdown.managingApplications
        onSectionChanged: hover.retain()
    }
    Timer { id: entryGrace; interval: 900; onTriggered: hover.retain() }
    MouseArea { anchors.fill: parent; onClicked: hover.close() }
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: hover.close()
        MenuPopover {
            id: popover
            anchors.fill: parent
            opened: hover.opened
            edge: "top"
            alignment: hover.group
            triggerRect: hover.revealRect
            preferredBodyWidth: Math.min(hover.width - 24, Math.max(240, (hover.controls?.groupLength(hover.group) || 0) + 56))
            maximumBodyHeight: 180
            showHeader: false
            wallpaperSource: hover.wallpaperSource
            translucency: hover.settings.bar?.popdownTranslucency ?? 0.06
            persistentSelected: true
            onHoverChanged: inside => {
                if (inside) entryGrace.stop();
                hover.retain();
            }
            persistentPage: Component {
                Column {
                    id: content
                    property alias controls: groupBar
                    spacing: 12
                    Text {
                        id: heading
                        text: "Hyprhover  ·  " + ({left: "Workspace", center: "At a glance", right: "System"})[hover.group]
                        color: popover.menuColors.accent
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Flickable {
                        id: viewport
                        width: parent.width
                        height: groupBar.implicitHeight
                        contentWidth: Math.max(width, groupBar.groupLength(hover.group))
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Bar {
                            id: groupBar
                            width: viewport.contentWidth
                            onlySide: hover.group
                            settings: Object.assign({}, hover.settings, {bar: Object.assign({}, hover.settings.bar, {
                                position: "top", centerItems: false, height: 44, hyprknots: false,
                                contentPaddingTop: 0, contentPaddingBottom: 0, contentPaddingLeft: 0, contentPaddingRight: 0,
                                fullBackground: false, edgeAttached: false
                            })})
                            statusIconsOnly: true
                            mediaMaximumWidth: 200
                            statusData: hover.statusData
                            mediaData: hover.mediaData
                            notificationData: hover.notificationData
                            clockText: hover.clockText
                            trayModel: hover.trayModel
                            outputName: hover.screen.name
                            wallpaperSource: hover.wallpaperSource
                            screenWidth: hover.width
                            screenHeight: hover.height
                            screenOffsetX: mapToItem(popover, 0, 0).x
                            screenOffsetY: mapToItem(popover, 0, 0).y
                            activeMenu: menuState.section
                            hoverPopdowns: menuState.hoverEnabled
                            onMenuHovered: name => menuState.hover(name)
                            onMenuLeft: name => menuState.leave(name)
                            onPreviewUnavailable: menuState.close()
                            onAction: (name, argument) => {
                                if (name === "workspace") { hover.close(); hover.services.workspace(argument); }
                                else if (name === "workspace-scroll") hover.services.scrollWorkspace(argument);
                                else if (name === "settings") hover.settingsRequested();
                                else menuState.activate(name);
                            }
                            onTrayAction: (item, source, button) => {
                                if (button === Qt.MiddleButton) item.secondaryActivate();
                                else if (button === Qt.RightButton || item.onlyMenu) {
                                    if (item.hasMenu) {
                                        let point = source.mapToItem(hover.contentItem, 0, source.height);
                                        item.display(hover, point.x, point.y);
                                    }
                                } else item.activate();
                            }
                            onTrayScroll: (item, event) => item.scroll(event.angleDelta.y || event.angleDelta.x, !event.angleDelta.y)
                        }
                    }
                    Text {
                        visible: groupBar.orderedItems(hover.group).length === 0
                        text: "No visible items in this group"
                        color: popover.menuColors.accent
                        font.pixelSize: 12
                    }
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
    Dropdown {
        id: dropdown
        screen: hover.screen
        panelBounds: Qt.rect(0, 0, hover.width, hover.height)
        services: hover.services
        applicationService: hover.applicationService
        inbox: hover.inbox
        mediaData: hover.mediaData
        previewWorkspace: hover.controls?.previewWorkspace || null
        section: hover.opened ? menuState.section : ""
        displayedSection: menuState.displayedSection
        pinned: menuState.pinned
        barEdge: "top"
        barRect: Qt.rect(popover.bodyX, popover.bodyY, popover.bodyWidth, popover.bodyHeight)
        triggerRect: {
            if (!hover.controls) return hover.revealRect;
            let rect = hover.controls.menuAnchorRect(menuState.displayedSection);
            let point = hover.controls.mapToItem(hover.contentItem, rect.x, rect.y);
            return Qt.rect(point.x, point.y, rect.width, rect.height);
        }
        alignment: hover.group
        alignToTrigger: true
        movePointerOnOpen: false
        accent: hover.controls?.menuAccent(menuState.displayedSection) || "#b4befe"
        wallpaperSource: hover.wallpaperSource
        translucency: Settings.popdownTranslucency(hover.settings, hover.controls?.menuItemId(menuState.displayedSection) || "")
        onCloseRequested: { menuState.close(); hover.retain(); }
        onSettingsRequested: hover.settingsRequested()
        onHoverChanged: inside => menuState.retain(inside)
        onManagingApplicationsChanged: if (managingApplications) menuState.pinned = true
    }
}
