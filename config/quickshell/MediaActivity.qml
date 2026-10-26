import QtQuick

// Keep audio detection independent of the title animation. Short titles and
// idle playback need no repeating timer, including non-MPRIS audio sources.
Item {
    id: activity
    property bool hasPlayer: false
    property bool hasStream: false
    property real peak: 0
    property string fullTitle: "Audio playing"
    readonly property bool audible: peak > 0.00015
    readonly property bool playing: hasPlayer || (hasStream && (audible || silence.running))
    readonly property var characters: Array.from(fullTitle)
    readonly property var ring: characters.concat(Array.from("   •   "))
    property real marqueeStarted: 0
    property string marquee: ""

    onAudibleChanged: {
        // A steady peak remains audible without polling; after the final peak
        // keep the same 900 ms grace period for gaps in non-MPRIS playback.
        if (audible) silence.stop();
        else silence.restart();
    }
    Timer { id: silence; objectName: "mediaSilenceHold"; interval: 900 }

    function resetMarquee() {
        marqueeStarted = Date.now();
        updateMarquee();
    }
    function updateMarquee() {
        marqueeTimer.stop();
        if (!playing) { marquee = ""; return; }
        if (characters.length <= 28) { marquee = fullTitle; return; }
        let elapsed = Math.max(0, Date.now() - marqueeStarted) % (2000 + ring.length * 300);
        let offset = elapsed < 2000 ? 0 : Math.floor((elapsed - 2000) / 300);
        marquee = Array.from({length: 28}, (_, i) => ring[(offset + i) % ring.length]).join("");
        // Wake only when the next character changes, including the initial
        // pause and wraparound. Recompute from time so delayed frames catch up.
        marqueeTimer.interval = Math.max(1, (offset === 0 ? 2300 : 2000 + (offset + 1) * 300) - elapsed);
        marqueeTimer.start();
    }
    onPlayingChanged: resetMarquee()
    onRingChanged: resetMarquee()
    Component.onCompleted: resetMarquee()
    Timer {
        id: marqueeTimer
        objectName: "mediaMarqueeTimer"
        onTriggered: activity.updateMarquee()
    }
}
