pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: monitor
    required property var services
    property var wallpaperSources: ({})
    property bool shown: true
    property var readings: ({})
    Process {
        id: collector
        command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("helpers/system-monitor.py").toString().replace(/^file:\/\//, ""))]
        running: monitor.shown && Quickshell.screens.length > 0
        stdout: SplitParser {
            onRead: line => {
                try { monitor.readings = JSON.parse(line); }
                catch (error) { console.warn("System monitor: invalid collector frame"); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("System monitor: " + text.trim()) }
        onExited: (code, status) => {
            if (code !== 0 && monitor.shown) console.warn("System monitor collector exited: " + code);
        }
    }
    PanelWindow {
        id: window
        screen: Quickshell.screens[0] ?? null
        // The window's resolved screen may change while its visibility changes.
        // Use the stable screen model rather than feeding that back into itself.
        visible: monitor.shown && Quickshell.screens.length > 0
        anchors { right: true; top: true }
        margins { right: 24; top: 64 }
        implicitWidth: Math.min(350, Math.max(240, (screen ? screen.width : 1920) - 48))
        implicitHeight: Math.min(view.implicitHeight, Math.max(1, (screen ? screen.height : 1080) - 120))
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "hyprshell-system-monitor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        SystemMonitorView {
            id: view
            anchors.fill: parent
            readings: monitor.readings
            battery: monitor.services.batteryInfo
            connection: monitor.services.statusData.network.tooltip || "Offline"
            bluetooth: monitor.services.statusData.bluetooth.tooltip || "Unavailable"
            wallpaperSource: window.screen ? monitor.wallpaperSources[window.screen.name] || "" : ""
            screenWidth: window.screen ? window.screen.width : 1920
            screenHeight: window.screen ? window.screen.height : 1080
            originX: screenWidth - window.width - window.margins.right
            originY: window.margins.top
        }
    }
}
