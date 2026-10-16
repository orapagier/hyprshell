pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "style" as Style

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
    property string sourceAddress: ""
    property string message: ""
    property bool streamStopped: false
    readonly property var source: windows.find(t => t.address === sourceAddress) || null
    readonly property var ownWindow: windows.find(isViewer) || null
    readonly property var choices: windows.filter(t => !isViewer(t) && !!t.wayland)
    readonly property bool fullscreen: !!(ownWindow && ownWindow.wayland && ownWindow.wayland.fullscreen)

    function isViewer(t) {
        let data = t ? t.lastIpcObject || {} : {};
        return data.pid === Quickshell.processId && (data.initialTitle === "Hyprview" || t.title === "Hyprview");
    }
    function selectWindow(t) {
        if (!t || isViewer(t)) return false;
        if (!t.wayland) {
            message = "This window has no capture handle yet. Try again or choose another window.";
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
        if (!selected) message = "Focus an application and press Super+V, or choose a window above.";
        else selectWindow(selected);
        visible = true;
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
        }
    }
    onSourceChanged: streamStopped = false

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: controls.implicitHeight + 20
            color: Style.Theme.background
            RowLayout {
                id: controls
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Label { text: "Hyprview"; color: Style.Theme.text; font.bold: true }
                ComboBox {
                    id: picker
                    objectName: "hyprviewPicker"
                    Layout.fillWidth: true
                    model: view.choices
                    textRole: "title"
                    displayText: view.source ? view.source.title : "Choose a window…"
                    currentIndex: view.choices.findIndex(t => t.address === view.sourceAddress)
                    onActivated: index => view.selectWindow(view.choices[index])
                    delegate: ItemDelegate {
                        required property var modelData
                        width: picker.width
                        text: modelData.title || (modelData.lastIpcObject || {}).class || "Untitled window"
                        highlighted: picker.highlightedIndex === index
                        required property int index
                    }
                }
                SettingsButton {
                    text: view.fullscreen ? "Windowed" : "Fullscreen"
                    implicitWidth: 110
                    enabled: !!view.ownWindow
                    onClicked: view.toggleFullscreen()
                }
                SettingsButton { text: "Close"; implicitWidth: 75; onClicked: view.dismiss() }
            }
        }
        Item {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                text: view.message || (view.streamStopped ? "Capture stopped. Choose the window again to retry."
                    : view.source ? "Waiting for the window’s video…"
                    : view.sourceAddress ? "The projected window was closed. Choose another window above."
                    : "Focus an application and press Super+V, or choose a window above.")
            }
        }
        Label {
            Layout.fillWidth: true
            padding: 8
            color: "#aaaaaa"
            text: "Super+V projects the active window · F11 fullscreen · Esc closes · View only"
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
    Shortcut { sequence: "F11"; enabled: view.visible; onActivated: view.toggleFullscreen() }
    Shortcut {
        sequence: "Escape"
        enabled: view.visible
        onActivated: { if (view.fullscreen) view.toggleFullscreen(); else view.dismiss(); }
    }
}
