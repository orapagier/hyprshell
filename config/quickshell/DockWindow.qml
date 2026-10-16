pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "SettingsModel.js" as Settings
import "DockModel.js" as Model

Item {
    id: window
    required property var output
    required property var service
    required property var config
    required property var utilities
    signal settingsRequested()
    property real paneThickness: 32
    property url wallpaperSource: ''
    signal interactionStarted()
    property string component: 'hyprdock'
    readonly property var panel: config.panels[component]
    readonly property string edge: panel.position
    readonly property bool vertical: edge === 'left' || edge === 'right'
    readonly property var monitor: Hyprland.monitorFor(output)
    readonly property var workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : null
    readonly property bool shown: Settings.panelVisible(config,component,output.name,workspace)
    readonly property var insets: Model.insets(config,component,output.name,workspace,paneThickness)
    readonly property rect dockRect: Qt.rect(dock.x+rail.originX,dock.y+rail.originY,dock.width,dock.height)
    readonly property var clients: { let revision = service.windowRows; return service.windows; }
    readonly property bool fullscreen: clients.some(w => w.workspace && w.workspace.id === workspace
        && (w.lastIpcObject?.fullscreen === 2 || w.wayland?.fullscreen === true))
    readonly property bool overlapped: clients.some(w => Model.overlaps(dockRect,w,monitor?.lastIpcObject || {},workspace))
    DockVisibility {
        id: visibility
        eligible: window.shown
        mode: window.panel.hideMode
        fullscreen: window.fullscreen
        fullscreenPolicy: window.panel.fullscreenPolicy || 'hide'
        overlapped: window.overlapped
        hovered: dockHover.hovered || revealHover.hovered
        interacting: popup.opened || !!dock.draggingId || (dock.activeFocus && dock.keyboardInteraction)
        onSuppressedChanged: if (suppressed) { window.closeMenu(); if (dock) dock.draggingId = ''; }
    }
    function closeMenu() { if (popup) popup.dismiss(); }
    onShownChanged: if (!shown) { closeMenu(); if (dock) dock.draggingId = ''; }
    onEdgeChanged: closeMenu()
    PanelWindow {
        id: rail
        screen: window.output
        visible: window.shown
        color:'transparent'
        readonly property real originX: window.edge === 'right' ? screen.width-margins.right-width : margins.left
        readonly property real originY: window.edge === 'bottom' ? screen.height-margins.bottom-height : margins.top
        anchors { top:window.edge !== 'bottom'; bottom:window.edge !== 'top'; left:window.edge !== 'right'; right:window.edge !== 'left' }
        margins {
            left:window.edge === 'left' ? window.panel.marginEdge : !window.vertical ? window.panel.marginEnds : 0
            right:window.edge === 'right' ? window.panel.marginEdge : !window.vertical ? window.panel.marginEnds : 0
            top:window.edge === 'top' ? window.panel.marginEdge : window.vertical ? window.insets.top + window.panel.marginEnds : 0
            bottom:window.edge === 'bottom' ? window.panel.marginEdge : window.vertical ? window.insets.bottom + window.panel.marginEnds : 0
        }
        implicitWidth:window.vertical ? dock.thickness : window.output.width - 2*window.panel.marginEnds
        implicitHeight:window.vertical ? Math.max(1,window.output.height-window.insets.top-window.insets.bottom-2*window.panel.marginEnds) : dock.thickness
        mask: Region { x:dock.x; y:dock.y; width:dock.width; height:visibility.shown ? dock.height : 0 }
        exclusiveZone:visibility.reserve ? Model.thickness(window.panel) + window.panel.windowGap : 0
        exclusionMode:visible ? ExclusionMode.Normal : ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace:window.component === 'hyprbar' ? 'hyprshell-taskbar' : 'hyprshell-dock'
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
        Dock {
            id:dock
            onXChanged: window.closeMenu()
            onYChanged: window.closeMenu()
            x: window.vertical ? 0 : Model.aligned(rail.width,width,window.panel.alignment)
            y: window.vertical ? Model.aligned(rail.height,height,window.panel.alignment) : 0
            opacity: visibility.shown ? 1 : 0
            enabled: visibility.shown
            trashFull: window.utilities.full
            HoverHandler { id: dockHover }
            Behavior on opacity { NumberAnimation { duration: window.config.accessibility?.reducedMotion || window.panel.animations === false ? 0 : 140 } }
            onUtilityRequested: (key,context,rect) => {
                if (key === 'settings') { window.closeMenu(); window.settingsRequested(); }
                else if (key === 'trash' && context) {
                    window.utilities.refresh();
                    popup.open('trash','',Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height));
                } else window.utilities.run(key);
            }
            width:implicitWidth; height:implicitHeight
            component:window.component; outputName:window.output.name; workspace:window.workspace
            service:window.service; config:window.config
            maximumLength:Math.max(1, (window.vertical ? rail.screen.height-window.insets.top-window.insets.bottom : rail.screen.width) - 2*window.panel.marginEnds)
            onInteractionStarted:window.interactionStarted()
            onDismissRequested: popup.dismiss()
            onItemHovered:(kind,key,rect) => popup.hoverItem(kind,key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onItemLeft:(kind,key,rect) => popup.leaveItem(kind,key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onLauncherRequested:rect => popup.open('launcher','',Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onGroupRequested:(key,rect) => popup.open('group',key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onPreviewsRequested:(key,rect) => popup.open('previews',key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
        }
    }
    // A separate 3px surface at the physical edge bridges any saved outside margin.
    PanelWindow {
        id: reveal
        screen: window.output
        visible: window.shown && !visibility.suppressed && window.panel.hideMode !== 'always'
        color: 'transparent'
        anchors { top:window.edge !== 'bottom'; bottom:window.edge !== 'top'; left:window.edge !== 'right'; right:window.edge !== 'left' }
        implicitWidth:window.vertical ? 3 : window.output.width
        implicitHeight:window.vertical ? window.output.height : 3
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:window.component === 'hyprbar' ? 'hyprshell-taskbar-reveal' : 'hyprshell-dock-reveal'
        mask:Region {
            x:window.vertical ? 0 : window.dockRect.x
            y:window.vertical ? window.dockRect.y : 0
            width:window.vertical ? 3 : dock.width
            height:window.vertical ? dock.height : 3
        }
        HoverHandler { id:revealHover }
    }
    DockPopup {
        id:popup
        component:window.component; taskGroups:dock.groups
        screen:window.output; service:window.service; edge:window.edge; wallpaperSource:window.wallpaperSource
        utilities:window.utilities
        dockRect: window.dockRect
    }
}
