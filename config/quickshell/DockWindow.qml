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
    property real paneThickness: 32
    property url wallpaperSource: ''
    signal interactionStarted()
    readonly property var panel: config.panels.hyprdock
    readonly property string edge: panel.position
    readonly property bool vertical: edge === 'left' || edge === 'right'
    readonly property var monitor: Hyprland.monitorFor(output)
    readonly property var workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : null
    readonly property bool shown: Settings.panelVisible(config,'hyprdock',output.name,workspace)
    readonly property var insets: Model.insets(config,'hyprdock',output.name,workspace,paneThickness)
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
        mask: Region { x:dock.x; y:dock.y; width:dock.width; height:dock.height }
        exclusiveZone:Model.thickness(window.panel) + window.panel.windowGap
        exclusionMode:visible ? ExclusionMode.Normal : ExclusionMode.Ignore
        WlrLayershell.namespace:'hyprshell-dock'
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
        Dock {
            id:dock
            onXChanged: window.closeMenu()
            onYChanged: window.closeMenu()
            anchors.centerIn:parent
            width:implicitWidth; height:implicitHeight
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
    DockPopup {
        id:popup
        screen:window.output; service:window.service; edge:window.edge; wallpaperSource:window.wallpaperSource
        dockRect: Qt.rect(dock.x+rail.originX,dock.y+rail.originY,dock.width,dock.height)
    }
}
