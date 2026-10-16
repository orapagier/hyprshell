pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

FloatingWindow {
    id: view
    title: "Hyprview"
    property bool projectionOpen: false
    property bool externalWindowed: false
    visible: projectionOpen && (!externalOutput || externalWindowed)
    implicitWidth: 960
    implicitHeight: 600
    minimumSize: Qt.size(400, 260)
    color: "black"
    property var windows: Hyprland.toplevels.values
    property var activeWindow: Hyprland.activeToplevel
    property var displays: Quickshell.screens
    property var monitors: Hyprland.monitors.values
    property string sourceAddress: ""
    property string message: ""
    property bool streamStopped: false
    readonly property var source: windows.find(t => t.address === sourceAddress) || null
    readonly property var ownWindow: windows.find(isViewer) || null
    readonly property var viewerHandle: ownWindow ? ownWindow.wayland : null
    readonly property bool fullscreen: externalView.visible || !!(viewerHandle && viewerHandle.fullscreen)
    readonly property var projectedOutput: externalView.visible ? externalOutput : null
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
        let externalNative = externalView.contentItem.Window.window;
        if (isViewer(selected) || (externalView.visible && externalNative && externalNative.active)) {
            if (projectionOpen) dismiss();
            else projectionOpen = true;
            return;
        }
        if (!selected) message = "Focus an application and press Super+V.";
        else selectWindow(selected);
        externalWindowed = false;
        projectionOpen = true;
    }
    function toggleFullscreen() {
        if (externalOutput) {
            externalWindowed = !externalWindowed;
            return;
        }
        if (ownWindow && ownWindow.wayland)
            ownWindow.wayland.fullscreen = !fullscreen;
    }
    function dismiss() {
        if (viewerHandle && viewerHandle.fullscreen) viewerHandle.fullscreen = false;
        projectionOpen = false;
    }
    onClosed: dismiss()
    onProjectionOpenChanged: {
        if (!projectionOpen) {
            sourceAddress = "";
            streamStopped = false;
            message = "";
            externalWindowed = false;
        }
    }
    onSourceChanged: streamStopped = false
    onExternalOutputChanged: externalWindowed = false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                refreshOutputs.restart();
        }
    }
    Timer { id: refreshOutputs; interval: 100; onTriggered: Hyprland.refreshMonitors() }

    // A layer surface covers the external output without moving/focusing a
    // toplevel window or issuing a fullscreen-output request (which can warp
    // the pointer). OnDemand accepts focus only through an explicit user action.
    PanelWindow {
        id: externalView
        screen: view.externalOutput
        visible: view.projectionOpen && !!view.externalOutput && !view.externalWindowed
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprshell-hyprview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        ProjectionSurface { anchors.fill: parent; capturing: externalView.visible }
    }
    ProjectionSurface { anchors.fill: parent; capturing: view.visible }

    component ProjectionSurface: Item {
        id: canvas
        required property bool capturing
        clip: true
        ScreencopyView {
            id: projection
            objectName: "hyprviewProjection"
            anchors.centerIn: parent
            captureSource: canvas.capturing && view.source && !view.streamStopped ? view.source.wayland : null
            live: canvas.capturing && !!view.source && !view.streamStopped
            paintCursor: false
            readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
            width: Math.min(canvas.width, canvas.height * ratio)
            height: width / ratio
            visible: hasContent && !view.streamStopped
            onStopped: if (canvas.capturing) view.streamStopped = true
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
        Shortcut { sequence: "F11"; enabled: canvas.capturing; onActivated: view.toggleFullscreen() }
        Shortcut {
            sequence: "Escape"
            enabled: canvas.capturing
            onActivated: { if (view.fullscreen) view.toggleFullscreen(); else view.dismiss(); }
        }
    }
}
