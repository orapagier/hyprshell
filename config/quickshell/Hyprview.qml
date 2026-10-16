pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

FloatingWindow {
    id: view
    title: "Hyprview"
    visible: false
    implicitWidth: 960
    implicitHeight: 600
    minimumSize: Qt.size(400, 260)
    color: "black"
    property var windows: Hyprland.toplevels.values
    property var activeWindow: Hyprland.activeToplevel
    property var displays: Quickshell.screens
    property var monitors: Hyprland.monitors.values
    property string autoOutputName: ""
    property string sourceAddress: ""
    property string message: ""
    property bool streamStopped: false
    readonly property var source: windows.find(t => t.address === sourceAddress) || null
    readonly property var ownWindow: windows.find(isViewer) || null
    readonly property var viewerHandle: ownWindow ? ownWindow.wayland : null
    readonly property bool fullscreen: !!(viewerHandle && viewerHandle.fullscreen)
    readonly property var externalOutput: {
        let primary = displays.find(s => /^(eDP|LVDS|DSI)/.test(s.name)) || displays[0];
        let external = displays.filter(s => {
            let monitor = monitors.find(m => m.name === s.name);
            let data = monitor ? monitor.lastIpcObject : null;
            return primary && s.name !== primary.name && data && !data.disabled
                && (!data.mirrorOf || data.mirrorOf === "none");
        });
        external.sort((a, b) => Number(!/^HDMI/.test(a.name)) - Number(!/^HDMI/.test(b.name)) || a.name.localeCompare(b.name));
        return external[0] || null;
    }

    function isViewer(t) {
        let data = t ? t.lastIpcObject || {} : {};
        return data.pid === Quickshell.processId && (data.initialTitle === "Hyprview" || t.title === "Hyprview");
    }
    function selectWindow(t) {
        if (!t || isViewer(t)) return false;
        if (!t.wayland) {
            message = "This window has no capture handle yet. Focus it and press Super+V to retry.";
            return false;
        }
        sourceAddress = t.address;
        streamStopped = false;
        message = "";
        return true;
    }
    function projectActive() {
        // Capture the selection before mapping the viewer changes keyboard focus.
        let selected = activeWindow;
        if (isViewer(selected)) {
            if (visible) dismiss();
            else visible = true;
            return;
        }
        if (!selected) message = "Focus an application and press Super+V.";
        else selectWindow(selected);
        visible = true;
        routeOutput.restart();
    }
    function placeOnOutput() {
        if (!visible || !viewerHandle) return;
        if (externalOutput) {
            viewerHandle.fullscreenOn(externalOutput);
            autoOutputName = externalOutput.name;
        } else if (autoOutputName) {
            viewerHandle.fullscreen = false;
            autoOutputName = "";
        }
    }
    function toggleFullscreen() {
        if (ownWindow && ownWindow.wayland)
            ownWindow.wayland.fullscreen = !fullscreen;
    }
    function dismiss() {
        if (fullscreen) toggleFullscreen();
        visible = false;
    }
    onClosed: dismiss()
    onVisibleChanged: {
        if (!visible) {
            sourceAddress = "";
            streamStopped = false;
            message = "";
            autoOutputName = "";
        }
        else routeOutput.restart();
    }
    onSourceChanged: streamStopped = false
    onViewerHandleChanged: routeOutput.restart()
    onExternalOutputChanged: routeOutput.restart()
    Timer { id: routeOutput; interval: 0; onTriggered: view.placeOnOutput() }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                refreshOutputs.restart();
        }
    }
    Timer { id: refreshOutputs; interval: 100; onTriggered: Hyprland.refreshMonitors() }

    Item {
        id: canvas
        anchors.fill: parent
        clip: true
        ScreencopyView {
            id: projection
            objectName: "hyprviewProjection"
            anchors.centerIn: parent
            captureSource: view.visible && view.source && !view.streamStopped ? view.source.wayland : null
            live: view.visible && !!view.source && !view.streamStopped
            paintCursor: true
            readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
            width: Math.min(canvas.width, canvas.height * ratio)
            height: width / ratio
            visible: hasContent && !view.streamStopped
            onStopped: view.streamStopped = true
        }
        Label {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 48)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: "#cccccc"
            visible: !!view.message || !view.source || !projection.hasContent || view.streamStopped
            text: view.message || (view.streamStopped ? "Capture stopped. Focus the source and press Super+V to retry."
                : view.source ? "Waiting for the window’s video…"
                : view.sourceAddress ? "The projected window was closed. Focus another application and press Super+V."
                : "Focus an application and press Super+V.")
        }
    }
    Shortcut { sequence: "F11"; enabled: view.visible; onActivated: view.toggleFullscreen() }
    Shortcut {
        sequence: "Escape"
        enabled: view.visible
        onActivated: { if (view.fullscreen) view.toggleFullscreen(); else view.dismiss(); }
    }
}
