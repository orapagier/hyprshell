pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import Quickshell.Hyprland

Item {
    id: preview
    readonly property var menuColors: Colors.menuColorsFor(preview)
    property int workspaceId: 0
    property var output: null
    property url wallpaperSource: ""
    property bool active: false
    property bool interactive: false
    signal activated(int workspaceId)
    property var windows: Hyprland.toplevels.values
    property var monitor: output ? Hyprland.monitorFor(output) : null
    readonly property var workspaceWindows: windows.filter(t => (t.workspace?.id ?? t.lastIpcObject?.workspace?.id) === workspaceId)
    readonly property real desktopWidth: Math.max(1, output ? output.width : 1920)
    readonly property real desktopHeight: Math.max(1, output ? output.height : 1080)
    implicitHeight: width * desktopHeight / desktopWidth
    clip: true
    onActiveChanged: if (active) Hyprland.refreshToplevels()
    Rectangle { anchors.fill: parent; radius: 8; color: "#181825" }
    Image { anchors.fill: parent; source: preview.wallpaperSource; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    Repeater {
        model: preview.workspaceWindows
        delegate: Rectangle {
            id: thumbnail
            required property var modelData
            readonly property var info: modelData.lastIpcObject || {}
            x: ((info.at?.[0] || 0) - (preview.monitor?.x || 0)) * preview.width / preview.desktopWidth
            y: ((info.at?.[1] || 0) - (preview.monitor?.y || 0)) * preview.height / preview.desktopHeight
            width: Math.max(1, (info.size?.[0] || preview.desktopWidth) * preview.width / preview.desktopWidth)
            height: Math.max(1, (info.size?.[1] || preview.desktopHeight) * preview.height / preview.desktopHeight)
            color: "#313244"
            border.color: "#6c7086"
            border.width: 1
            radius: 3
            clip: true
            PreviewCapture {
                id: capture
                anchors.fill: parent
                anchors.margins: 1
                source: thumbnail.modelData.wayland || null
                active: preview.active
            }
            Text {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 8)
                text: thumbnail.modelData.title || thumbnail.info.class || "Window"
                visible: !capture.hasContent
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: preview.menuColors.text
                font.pixelSize: 10
            }
        }
    }
    Text {
        anchors.centerIn: parent
        visible: preview.workspaceWindows.length === 0
        text: "Empty workspace"
        color: preview.menuColors.text
        font.pixelSize: 12
        style: Text.Outline
        styleColor: "#181825"
    }
    MouseArea {
        anchors.fill: parent
        enabled: preview.interactive && preview.workspaceId > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: preview.activated(preview.workspaceId)
    }

}
