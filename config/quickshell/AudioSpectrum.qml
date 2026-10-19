import QtQuick
import Quickshell.Io

Item {
    id: spectrum
    property string sinkName: ""
    enabled: false
    property var levels: Array(12).fill(0)
    readonly property bool wanted: enabled && sinkName.length > 0
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("helpers/audio-spectrum").toString().replace(/^file:\/\//, ""))
    function acceptFrame(frame) {
        if (!Array.isArray(frame) || frame.length !== 12
                || !frame.every(n => typeof n === "number" && isFinite(n) && n >= 0 && n <= 1)) return;
        // Silence and rounded, identical FFT frames need no new UI bindings.
        // Keep every changed frame at the helper's original delivery rate.
        if (frame.some((value, index) => value !== levels[index])) levels = frame;
    }
    function restart() {
        capture.running = false;
        levels = Array(12).fill(0);
        reconnect.interval = 100;
        if (wanted) reconnect.restart();
        else reconnect.stop();
    }
    onSinkNameChanged: Qt.callLater(restart)
    onWantedChanged: restart()
    Component.onCompleted: Qt.callLater(restart)
    Timer {
        id: reconnect
        interval: 100
        onTriggered: if (spectrum.wanted) capture.running = true
    }
    Process {
        id: capture
        objectName: "spectrumCapture"
        command: [spectrum.helper, spectrum.sinkName + ".monitor"]
        stdout: SplitParser {
            onRead: line => {
                if (!spectrum.wanted) return;
                try {
                    spectrum.acceptFrame(JSON.parse(line));
                } catch (error) { /* Ignore incomplete frames during shutdown. */ }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            spectrum.levels = Array(12).fill(0);
            // Output changes restart promptly; a lost audio server retries gently.
            if (spectrum.wanted && !reconnect.running) {
                reconnect.interval = 2000;
                reconnect.start();
            }
        }
    }
}
