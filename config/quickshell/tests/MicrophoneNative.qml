import QtQuick
import QtQuick.Window
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    QtObject { id: audio; property real volume: 0.5; property bool muted: false }
    QtObject { id: mic; property var audio: audio; property string name: "input with spaces;literal"; property string description: "Test input" }
    QtObject { id: other; property var audio: audio; property string name: "fail"; property string description: "Disconnected input" }
    QtObject { id: stalled; property var audio: audio; property string name: "stall"; property string description: "Stalled input" }
    QtObject { id: services; property var sink: null; property var microphone: mic; property var outputs: []; property var inputs: [mic, other]; property var applicationStreams: [] }
    Window { visible: true; width: 800; height: 1600; SettingsSound { id: page; width: 800; services: services } }
    function check(value, message) { if (!value) { console.error("MICROPHONE_FAILED", phase, message); Qt.quit(); throw new Error(message); } }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0) {
                test.check(!page.metering && !page.meterReady, "initially idle");
                page.meterEnabled = true;
                test.phase = 1;
            } else if (test.phase === 1 && page.meterReady) {
                test.check(page.inputPeak === 0.5 && page.inputLevels.length === 12 && page.inputLevels[5] === 0.5 && page.inputLevels[0] === 0 && !page.meterError, "default loader receives frequency bands");
                page.visible = false;
                test.check(!page.meterEnabled && !page.metering, "close stops capture");
                test.phase = 2;
            } else if (test.phase === 2) {
                page.visible = true; page.meterEnabled = true;
                test.phase = 3;
            } else if (test.phase === 3 && page.meterReady) {
                services.microphone = other;
                test.check(!page.meterEnabled && !page.metering, "device change stops capture");
                page.meterEnabled = true;
                test.phase = 4;
            } else if (test.phase === 4 && page.meterError) {
                test.check(page.meterError === "Input disconnected" && !page.meterReady && page.inputPeak === 0, "error shown");
                page.meterEnabled = false;
                test.check(!page.meterError, "stop clears error");
                services.microphone = stalled;
                page.meterEnabled = true;
                test.phase = 5;
            } else if (test.phase === 5 && page.meterReady) {
                test.check(page.inputPeak === 0.5, "initial stalled level");
                test.phase = 6;
            } else if (test.phase === 6 && page.meterError) {
                test.check(page.meterError.indexOf("stopped updating") >= 0 && !page.meterReady && page.inputPeak === 0, "stale data clears meter");
                console.log("MICROPHONE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.error("MICROPHONE_FAILED timeout", test.phase, page.meterEnabled, page.metering, page.meterReady, page.inputPeak, page.meterError); Qt.quit(); } }
}
