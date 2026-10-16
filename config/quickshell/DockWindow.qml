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
    property var desktopServices: null
    property var inbox: null
    property var statusData: ({workspaces:[],audio:{},network:{},bluetooth:{},battery:{}})
    property var mediaData: ({playing:false,levels:[],title:'',tooltip:''})
    property var notificationData: ({count:0})
    property var trayModel: []
    property string clockText: ''
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
    readonly property bool launcherAvailable: shown && !visibility.suppressed
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
        hovered: dockHover.hovered || revealHover.hovered || statusHover.hovered
        interacting: status.activeFocus || !!statusState.section || popup.opened || !!dock.draggingId || (dock.activeFocus && dock.keyboardInteraction)
        onSuppressedChanged: if (suppressed) { window.closeMenu(); if (dock) dock.draggingId = ''; }
    }
    MenuController { id:statusState }
    function closeMenu() { if (popup) popup.dismiss(); statusState.close(); }
    function toggleLauncher() {
        statusState.close();
        window.interactionStarted();
        let rect = dock.launcherRect();
        popup.open('launcher','',Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height));
    }
    function statusInteraction() { popup.dismiss(); window.interactionStarted(); }
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
            trailingLength: status.contentLength > 0 ? statusViewport.extent + 8 : 0
            onXChanged: window.closeMenu()
            onYChanged: window.closeMenu()
            x: window.vertical ? 0 : Model.aligned(rail.width,width,window.panel.alignment)
            y: window.vertical ? Model.aligned(rail.height,height,window.panel.alignment) : 0
            opacity: visibility.shown ? 1 : 0
            enabled: visibility.shown
            trashFull: window.utilities.full
            wallpaperSource:window.wallpaperSource
            screenWidth:window.output.width; screenHeight:window.output.height
            screenOffsetX:rail.originX+dock.x; screenOffsetY:rail.originY+dock.y
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
            onInteractionStarted: { statusState.close(); window.interactionStarted(); }
            onDismissRequested: popup.dismiss()
            onItemHovered:(kind,key,rect) => popup.hoverItem(kind,key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onItemLeft:(kind,key,rect) => popup.leaveItem(kind,key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onLauncherRequested:rect => popup.open('launcher','',Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onGroupRequested:(key,rect) => popup.open('group',key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
            onPreviewsRequested:(key,rect) => popup.open('previews',key,Qt.rect(rect.x+dock.x+rail.originX,rect.y+dock.y+rail.originY,rect.width,rect.height))
        }
        Flickable {
            id:statusViewport
            function revealItem(item) {
                let point=item.mapToItem(status,0,0);
                if(window.vertical) contentY=Math.max(0,Math.min(contentHeight-height,Math.max(point.y+item.height-height,Math.min(contentY,point.y))));
                else contentX=Math.max(0,Math.min(contentWidth-width,Math.max(point.x+item.width-width,Math.min(contentX,point.x))));
            }
            readonly property real extent: Math.min(status.contentLength, Math.max(0,dock.maximumLength - Math.max(148,dock.cellSize+76)))
            x:dock.x + (window.vertical ? 0 : dock.width-width-4)
            y:dock.y + (window.vertical ? dock.height-height-4 : 0)
            width:window.vertical ? rail.width : extent
            height:window.vertical ? extent : rail.height
            visible:visibility.shown && extent > 0
            contentWidth:window.vertical ? width : status.width
            contentHeight:window.vertical ? status.height : height
            clip:true; boundsBehavior:Flickable.StopAtBounds
            flickableDirection:window.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
            HoverHandler { id:statusHover }
            WheelHandler {
                target:null
                onWheel:event => {
                    let delta=(event.angleDelta.y || event.angleDelta.x)/3;
                    if(window.vertical) statusViewport.contentY=Math.max(0,Math.min(statusViewport.contentHeight-statusViewport.height,statusViewport.contentY-delta));
                    else statusViewport.contentX=Math.max(0,Math.min(statusViewport.contentWidth-statusViewport.width,statusViewport.contentX-delta));
                    event.accepted=true;
                }
            }
            TaskbarStatus {
                id:status
                config:window.config; edge:window.edge; component:window.component
                width:window.vertical ? statusViewport.width : contentLength
                height:window.vertical ? contentLength : statusViewport.height
                statusData:window.statusData; mediaData:window.mediaData; notificationData:window.notificationData
                trayModel:window.trayModel; clockText:window.clockText
                outputName:window.output.name; wallpaperSource:window.wallpaperSource
                screenWidth:window.output.width; screenHeight:window.output.height
                screenOffsetX:rail.originX+statusViewport.x-statusViewport.contentX
                screenOffsetY:rail.originY+statusViewport.y-statusViewport.contentY
                activeMenu:statusState.section
                onItemFocusRequested:item => statusViewport.revealItem(item)
                onPreviewUnavailable:statusState.close()
                onMenuHovered:name => { window.statusInteraction(); statusState.hover(name); }
                onMenuLeft:name => statusState.leave(name)
                onAction:(name,argument) => {
                    window.statusInteraction();
                    if(name === 'workspace') { statusState.close(); window.desktopServices?.workspace(argument); }
                    else if(name === 'workspace-scroll') window.desktopServices?.scrollWorkspace(argument);
                    else if(name === 'settings') { statusState.close(); window.settingsRequested(); }
                    else statusState.activate(name);
                }
                onTrayAction:(item,source,button) => {
                    window.statusInteraction();
                    if(button === Qt.MiddleButton) item.secondaryActivate();
                    else if(button === Qt.RightButton || item.onlyMenu) {
                        if(item.hasMenu) { let point=source.mapToItem(rail.contentItem,0,source.height); item.display(rail,point.x,point.y); }
                    } else item.activate();
                }
                onTrayScroll:(item,event) => item.scroll(event.angleDelta.y || event.angleDelta.x,!event.angleDelta.y)
            }
        }
    }
    Loader {
        active:status.contentLength > 0 && !!window.desktopServices && !!window.inbox
        sourceComponent: Component {
            Dropdown {
                screen:window.output; services:window.desktopServices; inbox:window.inbox
                applicationService:window.service; wallpaperSource:window.wallpaperSource
                section:statusState.section; displayedSection:statusState.displayedSection
                pinned:statusState.pinned; connected:true; movePointerOnOpen:false
                barEdge:window.edge; barRect:window.dockRect; alignment:'right'
                mediaData:window.mediaData; previewWorkspace:status.previewWorkspace
                accent:status.menuAccent(statusState.displayedSection)
                translucency:Settings.popdownTranslucency(window.config,status.menuItemId(statusState.displayedSection))
                triggerRect: {
                    let rect=status.menuRect(statusState.displayedSection);
                    return Qt.rect(rect.x+statusViewport.x-statusViewport.contentX+rail.originX,
                        rect.y+statusViewport.y-statusViewport.contentY+rail.originY,rect.width,rect.height);
                }
                onHoverChanged:inside => statusState.retain(inside)
                onCloseRequested:statusState.close()
                onSettingsRequested:window.settingsRequested()
                onManagingApplicationsChanged:if(managingApplications) statusState.pinned=true
            }
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
