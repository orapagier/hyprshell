pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popup
    required property var service
    readonly property string mode: menuState.mode
    readonly property string groupKey: menuState.groupKey
    readonly property rect triggerRect: menuState.triggerRect
    property rect dockRect: Qt.rect(0,0,0,0)
    property string edge: 'bottom'
    property url wallpaperSource: ''
    readonly property var group: service.groups('hyprdock').find(g => g.key === groupKey) || null
    readonly property bool opened: !!mode
    function dismiss() { menuState.close(); }
    function open(kind, key, rect) { menuState.activateItem(kind, key, rect); }
    function hoverItem(kind, key, rect) { menuState.hoverItem(kind, key, rect); }
    function leaveItem(kind, key, rect) { menuState.leaveItem(kind, key, rect); }
    DockMenuController { id: menuState }
    onGroupChanged: if ((mode === 'group' || mode === 'previews') && (!group || (mode === 'previews' && !group.windows.length))) dismiss()
    onOpenedChanged: if (opened) scope.forceActiveFocus()
    // Keep the surface mapped and the dock reachable while hovering neighboring items.
    visible: true
    anchors { top:true; bottom:true; left:true; right:true }
    color: 'transparent'
    exclusionMode: ExclusionMode.Ignore
    readonly property rect inputRect: edge === 'bottom' ? Qt.rect(0,0,width,dockRect.y)
        : edge === 'left' ? Qt.rect(dockRect.x+dockRect.width,0,width-dockRect.x-dockRect.width,height)
        : edge === 'right' ? Qt.rect(0,0,dockRect.x,height)
        : Qt.rect(0,dockRect.y+dockRect.height,width,height-dockRect.y-dockRect.height)
    mask: Region { x:popup.inputRect.x; y:popup.inputRect.y; width:Math.max(0,popup.inputRect.width); height:popup.opened ? Math.max(0,popup.inputRect.height) : 0 }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: 'hyprshell-dock-menu'
    WlrLayershell.keyboardFocus: !opened ? WlrKeyboardFocus.None : menuState.pinned ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    MouseArea { anchors.fill:parent; onClicked:popup.dismiss() }
    FocusScope {
        id: scope
        anchors.fill:parent; focus:true
        Keys.onEscapePressed: popup.dismiss()
        MenuPopover {
            id: popover
            anchors.fill:parent
            edge:popup.edge; triggerRect:popup.triggerRect; alignment:'center'
            opened:popup.opened; instant:true; alignToTrigger:true
            onHoverChanged: inside => menuState.retain(inside)
            wallpaperSource:popup.wallpaperSource
            showHeader: popup.mode !== 'previews'
            preferredBodyWidth: popup.mode === 'previews' ? (vertical ? 256 : Math.min(900, 36 + (popup.group?.windows.length || 1) * 228 - 8)) : 300
            title:popup.mode === 'launcher' ? 'Applications' : popup.mode === 'manage' ? 'Apps & windows' : popup.group ? popup.group.name : 'Application'
            symbol:popup.mode === 'launcher' ? '󰀻' : '󰘳'
            page:popup.mode === 'launcher' ? launcher : popup.mode === 'manage' ? manager : popup.mode === 'previews' ? previews : actions
        }
    }
    Shortcut { sequence:'Escape'; enabled:popup.opened; onActivated:popup.dismiss() }
    Component {
        id:launcher
        LauncherMenu {
            applicationService:popup.service; active:popup.opened
            onInteractingChanged: if (interacting) menuState.pinned = true
            onLaunched:popup.dismiss()
        }
    }
    Component { id:manager; ApplicationManager { service:popup.service } }
    Component {
        id: previews
        DockPreviews {
            service: popup.service; group: popup.group
            edge: popup.edge
            maximumHeight: Math.max(0, popover.availableHeight - 36)
            onCloseRequested: popup.dismiss()
        }
    }
    Component {
        id:actions
        DockActions {
            service:popup.service; group:popup.group
            onCloseRequested:popup.dismiss()
            onManageRequested:popup.open('manage',popup.groupKey,popup.triggerRect)
        }
    }
}
