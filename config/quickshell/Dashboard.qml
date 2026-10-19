pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: dashboard
    required property var services
    property url wallpaperSource: ""
    property real translucency: 0.06
    readonly property bool opened: menuState.section.length > 0
    readonly property bool pointerInside: popover.pointerInside
    readonly property rect inputRect: Qt.rect(4, 0, Math.max(0, width - 4), opened ? height : 0)
    property var resourceData: ({})
    property var previousCounters: null
    function reveal(output) {
        if (output) screen = output;
        menuState.section = "dashboard";
        menuState.pinned = false;
        menuState.retain(popover.pointerInside);
    }
    MenuController {
        id: menuState
        objectName: "dashboardMenuState"
        dismissPinnedOnLeave: true
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: edge
            required property var modelData
            screen: modelData
            // Never unmap the trigger during hover: that can leave a stale enter.
            visible: true
            anchors { left: true }
            implicitWidth: 4
            implicitHeight: 96
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hyprshell-dashboard-reveal"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        dashboard.screen = edge.modelData;
                        menuState.hover("dashboard");
                    } else menuState.leave("dashboard");
                }
            }
        }
    }
    signal settingsRequested()
    signal lockRequested()
    signal menuRequested(string name)
    function toggle(output) {
        if (opened) { menuState.close(); return; }
        if (output) screen = output;
        menuState.activate("dashboard", true);
        menuState.retain(popover.pointerInside);
        Qt.callLater(() => popover.pageItem?.focusFirst());
    }
    onOpenedChanged: {
        if (opened) {
            previousCounters = null;
            resourceData = ({});
            if (!sampler.running) sampler.running = true;
        }
    }
    // Match Dropdown: stay mapped and observe movement outside the card while
    // open, so Wayland reliably delivers exit from the menu and its bridge.
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-dashboard"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    Timer {
        interval: 2000; running: dashboard.opened; repeat: true
        onTriggered: if (!sampler.running) sampler.running = true
    }
    Process {
        id: sampler
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("helpers/dashboard-status.py").toString().replace(/^file:\/\//, ""))]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!dashboard.opened) return;
                try {
                    let next = JSON.parse(text), previous = dashboard.previousCounters;
                    let total = previous ? next.cpuTotal - previous.cpuTotal : 0;
                    next.cpuPercent = total > 0 ? Math.max(0, Math.min(100, 100 * (1 - (next.cpuIdle - previous.cpuIdle) / total))) : null;
                    dashboard.previousCounters = next;
                    dashboard.resourceData = next;
                } catch (e) { dashboard.resourceData = ({error: "Resource counters unavailable"}); }
            }
        }
        stderr: StdioCollector {}
    }
    mask: Region { x: dashboard.inputRect.x; y: dashboard.inputRect.y; width: dashboard.inputRect.width; height: dashboard.inputRect.height }
    MouseArea { anchors.fill: parent; onClicked: menuState.close() }
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: menuState.close()
        MenuPopover {
            id: popover
            objectName: "dashboardPopover"
            anchors.fill: parent
            edge: "left"
            triggerRect: Qt.rect(0, dashboard.height / 2 - 48, 4, 96)
            preferredBodyWidth: 1100
            opened: dashboard.opened
            wallpaperSource: dashboard.wallpaperSource
            translucency: dashboard.translucency
            showHeader: false
            persistentSelected: true
            persistentPage: dashboardPage
            onHoverChanged: inside => menuState.retain(inside)
        }
    }
    Component {
        id: dashboardPage
        DashboardContent {
            active: dashboard.opened
            services: dashboard.services
            resourceData: dashboard.resourceData
            onDismissRequested: menuState.close()
            onSettingsRequested: { menuState.close(); dashboard.settingsRequested(); }
            onLockRequested: { menuState.close(); dashboard.lockRequested(); }
            onMenuRequested: name => { menuState.close(); dashboard.menuRequested(name); }
        }
    }
}
