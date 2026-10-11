import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    QtObject { id: audio; property bool muted: false; property real volume: 0.5 }
    QtObject { id: sink; property var audio: audio; property string name: "device with spaces;$(literal)" }
    AudioInputMeter { id: inputMeter; node: null; enabled: false }
    SoundTest { id: tone; sink: sink }
    function check(value, message) { if (!value) { console.error("SOUND_FAILED", phase, message); Qt.quit(); throw new Error(message); } }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            test.ticks++;
            if (test.phase === 0) {
                test.check(!tone.busy && !tone.requested && !inputMeter.enabled && inputMeter.peak === 0, "starts idle");
                audio.muted = true;
                tone.play();
                test.check(!tone.requested && !tone.success && tone.message.indexOf("muted") >= 0 && audio.muted, "muted output");
                audio.muted = false; audio.volume = 0;
                tone.play();
                test.check(!tone.requested && !tone.success && audio.volume === 0, "zero volume");
                audio.volume = 0.5;
                tone.play(); tone.play();
                test.phase = 1;
            } else if (test.phase === 1 && !tone.busy && !tone.requested) {
                test.check(tone.success && tone.message.indexOf("finished") >= 0, "success");
                test.check(audio.volume === 0.5 && !audio.muted, "volume preserved");
                sink.name = "fail"; tone.play();
                test.phase = 2;
            } else if (test.phase === 2 && !tone.busy && !tone.requested) {
                test.check(!tone.success && tone.message.indexOf("Could not play") >= 0, "failure is actionable");
                sink.name = "slow"; tone.play();
                test.phase = 3; test.ticks = 0;
            } else if (test.phase === 3 && test.ticks > 2) {
                test.check(tone.busy, "slow player running");
                tone.visible = false;
                test.check(!tone.requested, "leave cancels request");
                test.phase = 4;
            } else if (test.phase === 4 && !tone.busy) {
                test.check(tone.message.indexOf("stopped") >= 0, "stopped on leave");
                tone.visible = true;
                sink.name = "slow"; tone.play();
                test.phase = 5; test.ticks = 0;
            } else if (test.phase === 5 && test.ticks > 2) {
                test.check(tone.busy, "second player running");
                sink.name = "replacement";
                test.check(!tone.requested, "device change cancels request");
                test.phase = 6;
            } else if (test.phase === 6 && !tone.busy) {
                tone.sink = null; tone.play();
                test.check(!tone.requested && !tone.success && tone.message.indexOf("available") >= 0, "missing device");
                tone.sink = sink; sink.name = "slow"; tone.play();
                test.phase = 7;
            } else if (test.phase === 7 && !tone.busy && !tone.requested) {
                test.check(!tone.success && tone.message.indexOf("timed out") >= 0, "timeout is actionable");
                console.log("SOUND_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.error("SOUND_FAILED timeout"); Qt.quit(); } }
}
