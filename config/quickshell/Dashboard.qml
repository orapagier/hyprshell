pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "style" as Style

PanelWindow {
    id: dashboard
    required property var services
    property bool opened: false
    property var resourceData: ({})
    property var previousCounters: null
    readonly property bool pointerInside: tracking.hovered
    property real revealProgress: opened ? 1 : 0
    Behavior on revealProgress {
        NumberAnimation { duration: Style.Theme.duration(dashboard, 350); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve }
    }
    function reveal(output) {
        if (output) screen = output;
        opened = true;
        leaveDelay.stop();
    }
    // A short grace period bridges surface handoff and permits reversing mid-slide.
    Timer {
        id: leaveDelay
        interval: 120
        onTriggered: if (!dashboard.pointerInside && !reveals.instances.some(r => r.hovered)) dashboard.opened = false
    }
    Variants {
        id: reveals
        model: Quickshell.screens
        PanelWindow {
            id: edge
            required property var modelData
            readonly property bool hovered: edgeHover.hovered
            screen: modelData
            visible: !dashboard.opened || dashboard.screen !== modelData
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
                id: edgeHover
                onHoveredChanged: {
                    if (hovered) dashboard.reveal(edge.modelData);
                    else if (dashboard.opened) leaveDelay.restart();
                }
            }
        }
    }
    signal settingsRequested()
    signal lockRequested()
    signal menuRequested(string name)
    function toggle(output) {
        if (opened) { opened = false; return; }
        if (output) screen = output;
        opened = true;
        Qt.callLater(() => content.focusFirst());
    }
    onOpenedChanged: {
        if (opened) {
            previousCounters = null;
            resourceData = ({});
            if (!sampler.running) sampler.running = true;
        }
    }
    visible: opened || revealProgress > 0
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
    // Only the dashboard accepts input; the rest of the desktop stays usable.
    mask: Region { item: hoverArea }
    Item {
        id: hoverArea
        objectName: "dashboardHoverArea"
        x: 0; y: card.y
        width: card.width; height: card.height
        HoverHandler {
            id: tracking
            onHoveredChanged: {
                if (hovered) leaveDelay.stop();
                else if (dashboard.opened) leaveDelay.restart();
            }
        }
    }
    Rectangle {
        id: card
        objectName: "dashboardCard"
        x: (dashboard.revealProgress - 1) * (width + 5)
        y: (dashboard.height - height) / 2
        width: Math.max(1, Math.min(1100, dashboard.width - 40))
        height: Math.max(1, Math.min(content.implicitHeight + 40, dashboard.height - 64))
        color: "#f21e1e2e"
        radius: 32
        border.width: 1
        border.color: "#22cdd6f4"
        opacity: Math.max(0, Math.min(1, dashboard.revealProgress))
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent; anchors.margins: 20
            contentWidth: width; contentHeight: content.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            DashboardContent {
                id: content
                width: parent.width
                active: dashboard.opened
                services: dashboard.services
                resourceData: dashboard.resourceData
                onDismissRequested: dashboard.opened = false
                onSettingsRequested: { dashboard.opened = false; dashboard.settingsRequested(); }
                onLockRequested: { dashboard.opened = false; dashboard.lockRequested(); }
                onMenuRequested: name => { dashboard.opened = false; dashboard.menuRequested(name); }
            }
        }
    }
}
