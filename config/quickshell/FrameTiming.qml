pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQml.Models

QtObject {
    id: recorder
    property var windows: []
    property bool recording: false
    property string captureId: ""
    property var samples: ({})
    property var previous: ({})
    function start(seconds) {
        if (recording) return false;
        captureId = Date.now().toString() + "-" + Math.random().toString(36).slice(2);
        samples = ({});
        previous = ({});
        timeout.interval = Math.max(1, Math.min(3600, seconds)) * 1000;
        recording = true;
        timeout.start();
        return true;
    }
    function record(key, now) {
        if (!recording) return;
        if (!samples[key]) samples[key] = {intervals: [], idleGaps: 0, dropped: 0};
        let row = samples[key];
        if (previous[key] !== undefined) {
            let delta = now - previous[key];
            // Windows need not repaint at idle. Keep those gaps separate from
            // frame cadence; this cannot distinguish a long stall from idle.
            if (delta > 250) row.idleGaps++;
            else if (delta > 0 && row.intervals.length < 10000) row.intervals.push(delta);
            else if (delta > 0) row.dropped++;
        }
        previous[key] = now;
    }
    function finish() {
        recording = false;
        timeout.stop();
        let result = {};
        for (let key of Object.keys(samples)) {
            let row = samples[key];
            let sorted = row.intervals.slice().sort((a,b) => a-b);
            let percentile = p => sorted.length ? sorted[Math.ceil(p * sorted.length) - 1] : null;
            result[key] = {intervals: sorted.length, median_ms: percentile(0.5),
                p95_ms: percentile(0.95), max_ms: sorted.length ? sorted[sorted.length-1] : null,
                gaps_over_250ms: row.idleGaps, samples_over_limit: row.dropped};
        }
        return result;
    }
    readonly property Timer timeout: Timer { onTriggered: recorder.recording = false }
    readonly property Instantiator observers: Instantiator {
        model: recorder.recording ? recorder.windows : []
        delegate: QtObject {
            id: observer
            required property var modelData
            readonly property Connections connection: Connections {
                target: observer.modelData.window?.contentItem?.Window.window ?? null
                function onFrameSwapped() { recorder.record(observer.modelData.name, Date.now()); }
            }
        }
    }
}
