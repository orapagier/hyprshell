pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: page
    property var services: null
    readonly property var sink: services ? services.sink : null
    readonly property var microphone: services ? services.microphone : null
    readonly property var outputs: services ? services.outputs || [] : []
    readonly property var inputs: services ? services.inputs || [] : []
    readonly property var streams: services ? services.applicationStreams || [] : []
    property var testSound: null
    readonly property bool busy: !!(testSound && (testSound.busy || testSound.requested))
    property bool meterEnabled: false
    readonly property bool metering: meter.active
    readonly property string meterError: meter.status === Loader.Error ? "Could not load the microphone test." : meter.item ? meter.item.error || "" : ""
    readonly property bool inputClipping: !!(meter.item && meter.item.clipping)
    readonly property bool meterReady: !!(meter.item && meter.item.ready)
    readonly property real inputPeak: meter.item ? meter.item.peak : 0
    readonly property var inputLevels: meter.item ? meter.item.levels || [] : []
    property Component meterComponent: null
    onVisibleChanged: if (!visible) { meterEnabled = false; if (testSound) testSound.stop(); }
    onMicrophoneChanged: meterEnabled = false
    spacing: 20
    SettingsCard {
        Layout.fillWidth: true
        title: "Output"
        subtitle: "Choose the default output for sound. Existing applications may keep their current device."
        SettingsComboBox {
            id: outputChoice
            objectName: "soundOutputControl"
            Layout.fillWidth: true
            model: page.outputs.length ? page.outputs.map(n => n.description || n.name) : ["No output device available"]
            currentIndex: page.outputs.length ? page.outputs.indexOf(page.sink) : 0
            enabled: page.outputs.length > 0
            onActivated: index => { if (page.outputs[index]) page.services.setOutput(page.outputs[index]); }
        }
        Label {
            Layout.fillWidth: true
            text: page.sink ? "Current output: " + (page.sink.description || page.sink.name) : "Audio output is unavailable. Check the device connection and PipeWire."
            color: page.sink ? Style.Theme.muted : Style.Theme.danger
            textFormat: Text.PlainText; wrapMode: Text.Wrap
        }
        SoundVolume { objectName: "soundOutputVolume"; Layout.fillWidth: true; node: page.sink; label: "Output volume" }
        SettingsButton {
            objectName: "soundTestControl"
            text: page.busy ? "Stop test sound" : "Play test sound"
            enabled: !!(page.sink && page.sink.audio)
            onClicked: if (page.testSound) { if (page.busy) page.testSound.stop(); else page.testSound.play(); }
        }
        Label {
            Layout.fillWidth: true
            text: (page.testSound ? page.testSound.message : "") || "Plays a short, quiet tone on the selected output. Your output volume and mute setting remain in effect."
            color: !page.testSound || page.testSound.success ? Style.Theme.muted : Style.Theme.danger
            wrapMode: Text.Wrap
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Microphone"
        subtitle: "Choose the default input for calls and recording. Existing applications may keep their current device."
        SettingsComboBox {
            objectName: "soundInputControl"
            Layout.fillWidth: true
            model: page.inputs.length ? page.inputs.map(n => n.description || n.name) : ["No microphone available"]
            currentIndex: page.inputs.length ? page.inputs.indexOf(page.microphone) : 0
            enabled: page.inputs.length > 0
            onActivated: index => { if (page.inputs[index]) page.services.setInput(page.inputs[index]); }
        }
        Label {
            Layout.fillWidth: true
            text: page.microphone ? "Current input: " + (page.microphone.description || page.microphone.name) : "Microphone is unavailable. Check the device connection and PipeWire."
            color: page.microphone ? Style.Theme.muted : Style.Theme.danger
            textFormat: Text.PlainText; wrapMode: Text.Wrap
        }
        SoundVolume { objectName: "soundInputVolume"; Layout.fillWidth: true; node: page.microphone; label: "Microphone volume"; showMutedAsZero: true }
        SettingsButton {
            objectName: "soundMeterControl"
            text: page.meterEnabled ? "Stop microphone test" : "Test microphone"
            enabled: !!(page.microphone && page.microphone.audio)
            onClicked: page.meterEnabled = !page.meterEnabled
        }
        Loader {
            id: meter
            active: page.visible && page.meterEnabled && !!page.microphone
            sourceComponent: page.meterComponent
            source: page.meterComponent ? "" : Qt.resolvedUrl("AudioInputMeter.qml")
            onLoaded: if (!page.meterComponent) {
                item.node = Qt.binding(() => page.microphone);
                item.enabled = Qt.binding(() => page.visible && page.meterEnabled);
            }
        }
        Rectangle {
            objectName: "soundInputMeter"
            Layout.fillWidth: true
            implicitHeight: 72
            visible: page.meterEnabled
            color: Style.Theme.surface; radius: 8
            Accessible.name: "Live microphone audio spectrum"
            AudioSpectrumBars {
                objectName: "soundInputSpectrum"
                anchors.centerIn: parent
                width: Math.max(0, Math.min(240, parent.width - 32))
                height: 48
                spacing: 5
                levels: page.inputLevels
                active: page.meterReady && !page.meterError && !!(page.microphone && page.microphone.audio && !page.microphone.audio.muted)
                color: page.inputClipping ? Style.Theme.danger : Style.Theme.success
            }
        }
        Label {
            Layout.fillWidth: true
            objectName: "soundInputStatus"
            text: page.meterEnabled ? page.meterError ? page.meterError : page.microphone && page.microphone.audio && page.microphone.audio.muted ? "Microphone is muted." : !page.meterReady ? "Starting microphone test…" : page.inputClipping ? "Input is clipping. Lower microphone volume and try speaking again." : "Speak to see your microphone’s live audio." : "Start the test to view the live input level. Audio is not saved or played back."
            wrapMode: Text.Wrap; color: page.meterError ? Style.Theme.danger : Style.Theme.muted
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Application volume"
        subtitle: "Control each running playback or recording stream. An application may have more than one stream."
        Label {
            Layout.fillWidth: true
            visible: page.streams.length === 0
            text: "No applications are using audio. Start playback or a call to show its controls."
            wrapMode: Text.Wrap; color: Style.Theme.muted
        }
        Repeater {
            model: page.streams
            delegate: SoundVolume {
                required property var modelData
                objectName: "soundAppVolume-" + modelData.id
                Layout.fillWidth: true
                node: modelData
                label: (modelData.properties["application.name"] || modelData.description || modelData.name) + (modelData.isSink ? " · Recording" : " · Playback")
            }
        }
    }
}
