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
    visible: opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-dashboard"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
    Rectangle {
        anchors.fill: parent
        color: "#66000000"
        opacity: dashboard.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.Theme.duration(dashboard, 200) } }
    }
    MouseArea { anchors.fill: parent; onClicked: dashboard.opened = false }
    Rectangle {
        id: card
        objectName: "dashboardCard"
        anchors.centerIn: parent
        width: Math.max(1, Math.min(1100, dashboard.width - 40))
        height: Math.max(1, Math.min(content.implicitHeight + 40, dashboard.height - 64))
        color: "#f21e1e2e"
        radius: 32
        border.width: 1
        border.color: "#22cdd6f4"
        opacity: dashboard.opened ? 1 : 0
        transform: Translate {
            y: dashboard.opened ? 0 : -24
            Behavior on y { NumberAnimation { duration: Style.Theme.duration(dashboard, 350); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
        }
        Behavior on opacity { NumberAnimation { duration: Style.Theme.duration(dashboard, 200); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
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
