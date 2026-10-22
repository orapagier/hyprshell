pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Layouts
import Quickshell.Hyprland
import "PreviewModel.js" as PreviewModel

ColumnLayout {
    id: preview
    readonly property var menuColors: Colors.menuColorsFor(preview)
    property var mediaData: ({})
    property bool active: false
    property var windows: Hyprland.toplevels.values
    readonly property var sourceWindow: PreviewModel.mediaWindow(windows, mediaData)
    spacing: 10
    onActiveChanged: if (active) Hyprland.refreshToplevels()
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: width * 9 / 16
        color: preview.menuColors.background
        radius: 8
        clip: true
        Image {
            id: artwork
            anchors.fill: parent
            anchors.margins: 4
            source: preview.mediaData.artUrl || ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: status === Image.Ready && !capture.hasContent
        }
        AudioSpectrumBars {
            anchors.centerIn: parent
            width: parent.width * 0.65; height: parent.height * 0.45
            levels: preview.mediaData.levels || []
            visible: !capture.hasContent && artwork.status !== Image.Ready
            color: preview.menuColors.accent
        }
        PreviewCapture {
            id: capture
            anchors.fill: parent
            source: preview.sourceWindow?.wayland || null
            active: preview.active
        }
    }
    MenuLabel {
        Layout.fillWidth: true
        text: preview.mediaData.trackTitle || preview.mediaData.fullTitle || preview.mediaData.tooltip || preview.mediaData.title || "Now playing"
        font.bold: true
        font.pixelSize: 13
    }
    MenuLabel {
        Layout.fillWidth: true
        text: [preview.mediaData.artist, preview.mediaData.appName].filter(Boolean).join(" · ")
        visible: text.length > 0
        font.pixelSize: 11
        color: preview.menuColors.secondary
    }
}
