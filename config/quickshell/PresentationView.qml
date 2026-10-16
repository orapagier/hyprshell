pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Copy the real laptop slideshow to HDMI. Keep ONLYOFFICE's own controls and
// keyboard focus on the laptop, and avoid moving/resizing its X11 slide canvas.
PanelWindow {
    id: window
    property var windows: Hyprland.toplevels.values
    property var displays: Quickshell.screens
    property var monitors: Hyprland.monitors.values
    readonly property var laptop: displays.find(s => /^(eDP|LVDS|DSI)/.test(s.name)) || null
    readonly property var slideshow: windows.find(t => {
        let data = t.lastIpcObject || {};
        return data.class === "ONLYOFFICE" && /\.pptx(?:\s|$)/i.test(t.title)
            && data.fullscreen === 2 && data.fullscreenClient === 2
            && t.monitor && laptop && t.monitor.name === laptop.name;
    }) || null
    readonly property var output: {
        let external = displays.filter(s => {
            let monitor = monitors.find(m => m.name === s.name);
            let data = monitor ? monitor.lastIpcObject : null;
            return laptop && s.name !== laptop.name && data && !data.disabled
                && (!data.mirrorOf || data.mirrorOf === "none");
        });
        external.sort((a, b) => Number(!/^HDMI/.test(a.name)) - Number(!/^HDMI/.test(b.name)) || a.name.localeCompare(b.name));
        return external[0] || null;
    }
    readonly property bool nativePresenter: slideshow !== null && windows.some(t => {
        let data = t.lastIpcObject || {};
        return t !== slideshow && data.class === "ONLYOFFICE"
            && data.pid === slideshow.lastIpcObject.pid
            && data.mapped === true && !data.hidden && data.fullscreenClient !== 2
            && (/presenter|reporter|speaker/i.test(t.title)
                || t.title === "ONLYOFFICE" || !t.title);
    })
    screen: output
    visible: !!(slideshow && slideshow.wayland && output && !nativePresenter)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "black"
    // No focus or synthetic keys: controls belong to the real laptop window.
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-presentation"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["fullscreen", "openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2", "monitoradded", "monitorremoved", "configreloaded"].indexOf(event.name) >= 0)
                refresh.restart();
        }
    }
    Timer {
        id: refresh
        interval: 100
        onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshMonitors(); }
    }
    ScreencopyView {
        id: projection
        objectName: "slideProjection"
        anchors.centerIn: parent
        captureSource: window.visible ? window.slideshow.wayland : null
        live: window.visible
        paintCursor: false
        // Explicit aspect fit: 1920x1080 becomes 1440x810 on a 1440x900
        // projector, with black bars rather than cropping or stretching.
        readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
        width: Math.min(window.width, window.height * ratio)
        height: width / ratio
    }
}
