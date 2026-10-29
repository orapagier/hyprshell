pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window
    required property var inbox
    property bool dockEnabled: false
    // One stack avoids duplicating alerts on every monitor.
    visible: !dockEnabled && inbox.popups.length > 0
    anchors { top: true; right: true }
    margins { top: 52; right: 16 }
    implicitWidth: screen ? Math.min(380, screen.width - 32) : 380
    implicitHeight: Math.min(stack.implicitHeight, screen ? screen.height - 84 : 720)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hyprshell-notifications"
    ScrollView {
        id: viewport
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Loader {
            id: stack
            width: viewport.availableWidth
            active: !window.dockEnabled
            sourceComponent: Component { NotificationPopupStack { inbox: window.inbox } }
        }
    }
}
