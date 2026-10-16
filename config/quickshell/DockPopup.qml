pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popup
    required property var service
    property string mode: ''
    property string groupKey: ''
    property rect triggerRect: Qt.rect(0,0,48,48)
    property string edge: 'bottom'
    property url wallpaperSource: ''
    readonly property var group: service.groups('hyprdock').find(g => g.key === groupKey) || null
    readonly property bool opened: !!mode
    function dismiss() { mode = ''; }
    function open(kind, key, rect) { groupKey = key; triggerRect = rect; mode = kind; }
    onGroupChanged: if ((mode === 'group' || mode === 'previews') && (!group || (mode === 'previews' && !group.windows.length))) dismiss()
    onOpenedChanged: if (opened) scope.forceActiveFocus()
    visible: opened
    anchors { top:true; bottom:true; left:true; right:true }
    color: 'transparent'
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: 'hyprshell-dock-menu'
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
            wallpaperSource:popup.wallpaperSource
            showHeader: popup.mode !== 'previews'
            preferredBodyWidth: popup.mode === 'previews' ? (vertical ? 256 : Math.min(900, 36 + (popup.group?.windows.length || 1) * 228 - 8)) : 300
            title:popup.mode === 'launcher' ? 'Applications' : popup.mode === 'manage' ? 'Apps & windows' : popup.group ? popup.group.name : 'Application'
            symbol:popup.mode === 'launcher' ? '󰀻' : '󰘳'
            page:popup.mode === 'launcher' ? launcher : popup.mode === 'manage' ? manager : popup.mode === 'previews' ? previews : actions
        }
    }
    Shortcut { sequence:'Escape'; enabled:popup.opened; onActivated:popup.dismiss() }
    Component { id:launcher; LauncherMenu { applicationService:popup.service; active:popup.opened; onLaunched:popup.dismiss() } }
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
            onManageRequested:popup.mode = 'manage'
        }
    }
}
