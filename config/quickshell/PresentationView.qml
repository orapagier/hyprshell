pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "style" as Style

// A normal ONLYOFFICE slideshow has no second presenter window. Give the
// laptop a live view and controls without duplicating the entire desktop.
PanelWindow {
    id: window
    property var windows: Hyprland.toplevels.values
    property var displays: Quickshell.screens
    property var send: command => Hyprland.dispatch(command)
    readonly property var slideshow: windows.find(t => {
        let data = t.lastIpcObject || {};
        return data.class === "ONLYOFFICE" && /\.pptx(?:\s|$)/i.test(t.title)
            && data.fullscreen === 2 && data.fullscreenClient === 2
            && t.monitor && !/^(eDP|LVDS|DSI)/.test(t.monitor.name);
    }) || null
    readonly property var laptop: displays.find(s => /^(eDP|LVDS|DSI)/.test(s.name)) || null
    readonly property var output: slideshow ? displays.find(s => s.name === slideshow.monitor.name) || null : null
    // Leave the application's native presenter window available when selected.
    readonly property bool nativePresenter: slideshow !== null && windows.some(t => {
        let data = t.lastIpcObject || {};
        return t !== slideshow && data.class === "ONLYOFFICE"
            && data.pid === slideshow.lastIpcObject.pid && data.acceptsInput !== false
            && data.visible !== false && data.fullscreen !== 2
            && (/presenter|reporter|speaker/i.test(t.title)
                || t.title === "ONLYOFFICE" || t.title === slideshow.title);
    })
    screen: laptop
    visible: !!(slideshow && laptop && output && laptop.name !== output.name && !nativePresenter)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Style.Theme.background
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "hyprshell-presentation"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function control(key) {
        if (!slideshow || !/^(Left|Right|Home|End|Escape)$/.test(key)) return;
        let address = slideshow.address.replace(/^0x/, "");
        if (!/^[0-9a-f]+$/i.test(address)) return;
        send('hl.dsp.send_shortcut({ mods = "", key = "' + key
             + '", window = "address:0x' + address + '" })');
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["fullscreen", "openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2"].indexOf(event.name) >= 0)
                refresh.restart();
        }
    }
    Timer { id: refresh; interval: 100; onTriggered: Hyprland.refreshToplevels() }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 16
        focus: window.visible
        Keys.onPressed: event => {
            let key = "";
            if ([Qt.Key_Right, Qt.Key_Down, Qt.Key_Space, Qt.Key_PageDown].indexOf(event.key) >= 0) key = "Right";
            else if ([Qt.Key_Left, Qt.Key_Up, Qt.Key_Backspace, Qt.Key_PageUp].indexOf(event.key) >= 0) key = "Left";
            else if (event.key === Qt.Key_Home) key = "Home";
            else if (event.key === Qt.Key_End) key = "End";
            else if (event.key === Qt.Key_Escape) key = "Escape";
            if (key) { window.control(key); event.accepted = true; }
        }
        Label {
            text: window.slideshow ? window.slideshow.title : "Presentation"
            color: Style.Theme.text
            font.pixelSize: 22
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Rectangle {
            id: previewArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "black"
            clip: true
            ScreencopyView {
                id: preview
                anchors.centerIn: parent
                captureSource: window.visible ? (window.slideshow.wayland || window.output) : null
                live: window.visible
                constraintSize: Qt.size(previewArea.width, previewArea.height)
                width: implicitWidth
                height: implicitHeight
            }
            Label {
                anchors.centerIn: parent
                visible: !preview.hasContent
                text: "Waiting for slide preview…"
                color: "white"
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16
            SettingsButton { objectName: "previousSlide"; text: "← Previous"; onClicked: window.control("Left") }
            SettingsButton { objectName: "nextSlide"; text: "Next →"; onClicked: window.control("Right") }
            SettingsButton { objectName: "endSlideshow"; text: "End slideshow"; onClicked: window.control("Escape") }
        }
        Label {
            text: "Arrow keys or Space to advance · Esc to end"
            color: Style.Theme.text
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
