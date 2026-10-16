import QtQuick
import Quickshell.Wayland

Item {
    id: preview
    property var source: null
    property bool active: false
    property bool stopped: false
    readonly property bool hasContent: capture.hasContent && !stopped
    onSourceChanged: stopped = false
    onActiveChanged: if (active) stopped = false
    clip: true
    ScreencopyView {
        id: capture
        objectName: "previewCapture"
        anchors.centerIn: parent
        captureSource: preview.active && !preview.stopped ? preview.source : null
        live: preview.active && !!preview.source && !preview.stopped
        paintCursor: false
        constraintSize: Qt.size(preview.width, preview.height)
        width: sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize.width * Math.min(preview.width / sourceSize.width, preview.height / sourceSize.height) : preview.width
        height: sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize.height * Math.min(preview.width / sourceSize.width, preview.height / sourceSize.height) : preview.height
        visible: preview.hasContent
        onStopped: preview.stopped = true
    }
}
