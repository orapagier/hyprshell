import QtQuick

Item {
    id: reveal
    property string edge: "top"
    property bool autoHide: false
    property bool menuOpen: false
    property bool motionEnabled: true
    property bool hoverHeld: false
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool revealed: !autoHide || hoverHeld || menuOpen
    property real progress: revealed ? 1 : 0
    readonly property real depth: Math.max(2, Math.min(1, progress) * (vertical ? width : height))
    readonly property rect inputRect: Qt.rect(
        autoHide && edge === "right" ? width - depth : 0,
        autoHide && edge === "bottom" ? height - depth : 0,
        vertical && autoHide ? depth : width,
        !vertical && autoHide ? depth : height)
    Behavior on progress {
        NumberAnimation {
            duration: !reveal.motionEnabled ? 0 : reveal.revealed ? 650 : 220
            easing.type: reveal.revealed ? Easing.OutElastic : Easing.InCubic
            easing.amplitude: 0.65
            easing.period: 0.55
        }
    }
    HoverHandler {
        onHoveredChanged: {
            if (hovered) { hideDelay.stop(); reveal.hoverHeld = true; }
            else hideDelay.restart();
        }
    }
    Timer { id: hideDelay; interval: 420; onTriggered: reveal.hoverHeld = false }
}
