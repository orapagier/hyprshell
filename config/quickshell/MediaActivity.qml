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
        if (!playing) { marquee = ""; return; }
        if (characters.length <= 28) { marquee = fullTitle; return; }
        let elapsed = ((Date.now() - marqueeStarted) / 1000) % (2 + ring.length * 0.3);
        let offset = elapsed < 2 ? 0 : Math.floor((elapsed - 2) / 0.3);
        marquee = Array.from({length: 28}, (_, i) => ring[(offset + i) % ring.length]).join("");
    }
    onPlayingChanged: resetMarquee()
    onRingChanged: resetMarquee()
    Component.onCompleted: resetMarquee()
    Timer {
        objectName: "mediaMarqueeTimer"
        interval: 67; repeat: true
        running: activity.playing && activity.characters.length > 28
        onTriggered: activity.updateMarquee()
    }
}
