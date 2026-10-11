pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: control
    required property var node
    property string label: "Volume"
    property bool showMutedAsZero: false
    readonly property bool available: !!(node && node.audio)
    readonly property bool displayMuted: available && showMutedAsZero && node.audio.muted
    spacing: 6
    RowLayout {
        Layout.fillWidth: true
        Label { Layout.fillWidth: true; text: control.label; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Style.Theme.text }
        Label { text: control.displayMuted ? "Muted" : control.available ? Math.round(control.node.audio.volume * 100) + "%" : "—"; color: Style.Theme.accentText }
        SettingsButton {
            objectName: "soundMuteControl"
            text: control.available && control.node.audio.muted ? "Unmute" : "Mute"
            enabled: control.available
            onClicked: control.node.audio.muted = !control.node.audio.muted
        }
    }
    Slider {
        id: slider
        objectName: "soundVolumeControl"
        Layout.fillWidth: true
        implicitHeight: 32
        from: 0; to: 1; stepSize: 0.01
        enabled: control.available
        value: control.available && !control.displayMuted ? control.node.audio.volume : 0
        onMoved: if (control.available) {
            let volume = value;
            control.node.audio.volume = volume;
            if (control.showMutedAsZero && volume > 0) control.node.audio.muted = false;
        }
        Accessible.name: control.label
        background: Rectangle {
            implicitWidth: 200; implicitHeight: 4
            x: slider.leftPadding; y: slider.height / 2 - height / 2
            width: slider.availableWidth; height: implicitHeight; radius: 2; color: Style.Theme.controlBorder
            Rectangle { width: slider.visualPosition * parent.width; height: 4; radius: 2; color: Style.Theme.accentText }
        }
        handle: Rectangle { x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width); y: slider.height / 2 - height / 2; implicitWidth: 14; implicitHeight: 14; radius: 7; color: Style.Theme.accentForeground }
    }
}
