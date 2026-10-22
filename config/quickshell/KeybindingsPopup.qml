pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: popup
    property url wallpaperSource: ""
    property real translucency: 0.06
    GlassSurface {
        id: glass
        wallpaperSource: popup.wallpaperSource
        screenWidth: popup.width; screenHeight: popup.height
        region: Qt.rect(card.x, card.y, card.width, card.height)
        translucency: popup.translucency
    }
    readonly property var menuColors: glass.menuColors
    property bool opened: false
    property bool pointerReady: false
    onOpenedChanged: {
        pointerReady = false;
        headerPointer.stop();
        if (opened) {
            headerPointer.restart();
            pointerDelay.restart();
        } else pointerDelay.stop();
    }
    // Move into the header before mouse-leave dismissal becomes active.
    Timer {
        id: headerPointer
        interval: 100
        onTriggered: {
            if (!popup.opened) return;
            let monitor = Hyprland.monitorFor(popup.screen);
            if (!monitor) return;
            let header = headerRow.mapToItem(popup.contentItem, headerRow.width / 2, headerRow.height / 2);
            let x = Math.round(monitor.x + header.x);
            let y = Math.round(monitor.y + header.y);
            Hyprland.dispatch("hl.dsp.cursor.move({ x = " + x + ", y = " + y + " })");
        }
    }
    Timer { id: pointerDelay; interval: 150; onTriggered: popup.pointerReady = true }
    visible: opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-keybindings"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    QtObject {
        id: theme
        readonly property color windowText: popup.menuColors.text
        readonly property color text: windowText
        readonly property color highlight: popup.menuColors.accent
        readonly property color highlightedText: popup.menuColors.background
        readonly property color base: popup.menuColors.background
    }
    function containsPoint(x, y) {
        return x >= card.x && x <= card.x + card.width && y >= card.y && y <= card.y + card.height;
    }
    // Opening does not dismiss the popup just because the pointer starts outside.
    // Moving outside subsequently dismisses it and returns focus to the desktop.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => { if (popup.pointerReady && !popup.containsPoint(mouse.x, mouse.y)) popup.opened = false; }
        onClicked: mouse => { if (!popup.containsPoint(mouse.x, mouse.y)) popup.opened = false; }
    }
    Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 8
        width: card.width + 10; height: card.height + 10
        radius: 25; color: "#28000000"
    }
    Rectangle {
        id: card
        readonly property var menuColors: popup.menuColors
        anchors.centerIn: parent
        width: Math.min(520, popup.width - 40)
        height: Math.min(600, popup.height - 40)
        radius: 22
        gradient: Gradient {
            GradientStop { position: 0; color: glass.topColor }
            GradientStop { position: 1; color: glass.bottomColor }
        }
        border.color: glass.rimColor
        border.width: 1
        // Consume card clicks so only clicks outside dismiss the popup.
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18
            Item {
                id: headerRow
                Layout.fillWidth: true
                implicitHeight: 44
                Rectangle {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 44
                    implicitWidth: 44; implicitHeight: 44; radius: 14
                    color: Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.14)
                    border.color: Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.24)
                    Text { anchors.centerIn: parent; text: "⌘"; color: theme.highlight; font.pixelSize: 25 }
                }
                ColumnLayout {
                    anchors.left: headerIcon.right
                    anchors.leftMargin: 14
                    anchors.right: escapeBadge.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Label { text: "Keyboard shortcuts"; color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 21; font.weight: Font.DemiBold }
                    Label { text: "Find your next move"; color: theme.windowText; opacity: 0.82; font.family: "Noto Sans"; font.pixelSize: 12 }
                }
                Rectangle {
                    id: escapeBadge
                    anchors.right: parent.right
                    anchors.top: headerIcon.top
                    width: 36; height: 25; radius: 7
                    color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.06)
                    Text { anchors.centerIn: parent; text: "esc"; color: theme.windowText; opacity: 0.82; font.family: "Noto Sans"; font.pixelSize: 11 }
                }
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: popup.opened
                sourceComponent: Component { KeybindingsMenu {} }
            }
        }
    }
    Shortcut { sequence: "Escape"; enabled: popup.opened; onActivated: popup.opened = false }
}
