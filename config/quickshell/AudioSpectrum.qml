import QtQuick
import Quickshell.Io

Item {
    id: spectrum
    property string sinkName: ""
    enabled: false
    property var levels: Array(12).fill(0)
    readonly property bool wanted: enabled && sinkName.length > 0
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("helpers/audio-spectrum").toString().replace(/^file:\/\//, ""))
    function validFrame(frame) {
        return Array.isArray(frame) && frame.length === 12
                && frame.every(n => typeof n === "number" && isFinite(n) && n >= 0 && n <= 1);
    }
    function acceptFrame(frame) {
        if (!validFrame(frame)) return;
        // Silence and rounded, identical FFT frames need no new UI bindings.
        // Changed frames apply immediately; the live pipeline coalesces through offerFrame.
        if (frame.some((value, index) => value !== levels[index])) levels = frame;
    }
    property var pendingFrame: null
    // The helper streams one frame per audio hop (~62/s). Applying every hop
    // re-evaluates the whole binding/animation chain and repaints the bars each
    // time for no visible gain, so coalesce to at most one delivery per interval.
    // Each extra delivery/s costs about a core-percent while media plays; 200 ms
    // keeps the bars lively at 5 Hz while the 40 ms Behavior smooths the steps.
    function offerFrame(frame) {
        if (!validFrame(frame)) return;
        if (!frame.some((value, index) => value !== levels[index])) return;
        pendingFrame = frame;
        if (!applyFrame.running) applyFrame.start();
    }
    Timer {
        id: applyFrame
        interval: 200
        onTriggered: {
            let frame = spectrum.pendingFrame;
            spectrum.pendingFrame = null;
            if (frame) spectrum.acceptFrame(frame);
        }
    }
    function restart() {
        capture.running = false;
        pendingFrame = null;
        applyFrame.stop();
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
                    spectrum.offerFrame(JSON.parse(line));
                } catch (error) { /* Ignore incomplete frames during shutdown. */ }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            spectrum.pendingFrame = null;
            spectrum.levels = Array(12).fill(0);
            // Output changes restart promptly; a lost audio server retries gently.
            if (spectrum.wanted && !reconnect.running) {
                reconnect.interval = 2000;
                reconnect.start();
            }
        }
    }
}
