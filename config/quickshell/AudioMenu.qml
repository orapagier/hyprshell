pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    required property var services
    spacing: 10
    Repeater {
        model: [{label: "Sound", node: page.services.sink}, {label: "Microphone", node: page.services.microphone}]
        delegate: ColumnLayout {
            id: section
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                MenuButton {
                    text: section.modelData.label === "Sound" ? page.services.audioIcon || "󰕾" : section.modelData.node && section.modelData.node.audio && section.modelData.node.audio.muted ? "󰍭" : "󰍬"
                    font.family: "GoMono Nerd Font"; font.pixelSize: 20
                    enabled: !!(section.modelData.node && section.modelData.node.audio)
                    onClicked: section.modelData.node.audio.muted = !section.modelData.node.audio.muted
                }
                MenuLabel { text: section.modelData.label; Layout.fillWidth: true; font.bold: true }
                MenuLabel { text: section.modelData.node && section.modelData.node.audio ? Math.round(section.modelData.node.audio.volume * 100) + "%" : "—"; color: page.menuColors.accent }
            }
            Slider {
                id: volume
                Layout.fillWidth: true
                // Custom visuals need a nonzero hit area for mouse dragging.
                implicitHeight: 28
                from: 0; to: 1; stepSize: 0.01
                enabled: !!(section.modelData.node && section.modelData.node.audio)
                value: enabled ? section.modelData.node.audio.volume : 0
                onMoved: section.modelData.node.audio.volume = value
                background: Rectangle {
                    implicitWidth: 200; implicitHeight: 4
                    x: volume.leftPadding; y: volume.height / 2 - height / 2
                    width: volume.availableWidth; height: implicitHeight; radius: 2; color: "#1fffffff"
                    Rectangle { width: volume.visualPosition * parent.width; height: 4; radius: 2; color: page.menuColors.accent }
                }
                handle: Rectangle { x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width); y: volume.height / 2 - height / 2; implicitWidth: 12; implicitHeight: 12; radius: 6; color: page.menuColors.text }
            }
            MenuLabel { text: section.modelData.node ? section.modelData.node.description : "Unavailable"; font.pixelSize: 11; color: page.menuColors.secondary; Layout.fillWidth: true }
        }
    }
    MenuLabel { text: "Output device"; font.bold: true }
    Repeater {
        model: page.services.outputs
        delegate: MenuButton {
            required property var modelData
            Layout.fillWidth: true
            text: (page.services.sink === modelData ? "✓  " : "    ") + modelData.description
            accent: page.services.sink === modelData ? page.menuColors.accent : page.menuColors.text
            onClicked: page.services.setOutput(modelData)
        }
    }
    MenuLabel { text: "Input device"; font.bold: true }
    Repeater {
        model: page.services.inputs || []
        delegate: MenuButton {
            required property var modelData
            Layout.fillWidth: true
            text: (page.services.microphone === modelData ? "✓  " : "    ") + modelData.description
            accent: page.services.microphone === modelData ? page.menuColors.accent : page.menuColors.text
            onClicked: page.services.setInput(modelData)
        }
    }

}
