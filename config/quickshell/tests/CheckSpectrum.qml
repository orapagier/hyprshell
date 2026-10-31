import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: check
    property var capture
    property int stage: 0
    property int received: 0
    property int updates: 0
    function assertThat(condition, message) {
        if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message); }
    }
    AudioSpectrum {
        id: spectrum
        onLevelsChanged: {
            check.updates++;
            if (levels[8] > 0.6) check.received++;
        }
    }
    MediaPill { id: pill; levels: spectrum.levels; text: "Native pipeline" }
    Component.onCompleted: {
        spectrum.acceptFrame(Array(12).fill(0));
        updates = 0;
        for (let i = 0; i < 63; ++i) spectrum.acceptFrame(Array(12).fill(0));
        assertThat(updates === 0, "duplicate silence frames do not invalidate UI");
        for (let i = 1; i <= 63; ++i) spectrum.acceptFrame(Array(12).fill(i / 63));
        assertThat(updates === 63, "every changed spectrum frame is delivered");
        spectrum.acceptFrame(Array(12).fill(1));
        for (let invalid of [[], Array(12).fill(NaN), Array(12).fill(-1), Array(12).fill(2), Array(12).fill("1")])
            spectrum.acceptFrame(invalid);
        assertThat(updates === 63 && spectrum.levels[0] === 1, "duplicates and invalid frames do not update UI");
        spectrum.acceptFrame(Array(12).fill(0));
        received = 0;
        for (let i = 0; i < spectrum.data.length; ++i)
            if (spectrum.data[i].objectName === "spectrumCapture") capture = spectrum.data[i];
        assertThat(!!capture, "capture object exists");
        spectrum.sinkName = "test-speaker";
        assertThat(capture.command[1] === "--coalesce" && capture.command[2] === "test-speaker.monitor", "coalesced explicit speaker monitor");
        // Feed FFT frames through a real Process/SplitParser, with no audio socket.
        capture.stdinEnabled = true;
        capture.command = Qt.binding(() => ["sh", "-c", 'cat "$1"; exec cat', "_",
            Quickshell.env("QUICKSHELL_SPECTRUM_TEST_FRAMES"), spectrum.sinkName + ".monitor"]);
        spectrum.enabled = true;
    }
    Timer {
        interval: 350; running: true; repeat: true
        onTriggered: {
            if (check.stage === 0) {
                check.assertThat(check.received > 0 && spectrum.levels[8] > 0.6, "FFT frames reach QML");
                check.assertThat(pill.levels[8] === spectrum.levels[8], "renderer receives live bands");
                spectrum.enabled = false;
            } else if (check.stage === 1) {
                check.assertThat(!check.capture.running && spectrum.levels.every(n => n === 0), "idle stops capture and clears bars");
                check.received = 0;
                spectrum.enabled = true;
            } else if (check.stage === 2) {
                check.assertThat(check.received > 0 && check.capture.running, "playback restarts capture");
                check.received = 0;
                spectrum.sinkName = "test-headset";
            } else if (check.stage === 3) {
                check.assertThat(check.received > 0 && check.capture.running, "output switch reconnects");
                check.assertThat(check.capture.command[5] === "test-headset.monitor", "new monitor selected");
                spectrum.sinkName = "";
            } else {
                check.assertThat(!check.capture.running && spectrum.levels.every(n => n === 0), "missing sink stops capture");
                console.log("PASS: native FFT-to-QML pipeline, playback lifecycle, and output switching");
                Qt.quit();
            }
            check.stage++;
        }
    }
}
