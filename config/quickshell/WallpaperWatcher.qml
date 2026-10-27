import QtQuick
import Quickshell
import Quickshell.Io
import "WallpaperQuery.js" as Query

QtObject {
    id: watcher
    property var sources: ({})
    property string response: ""
    property int retryInterval: 2000
    property bool eventsReady: false
    property bool queryPending: false
    function requestQuery() {
        if (query.running) queryPending = true;
        else query.running = true;
    }
    readonly property Process events: Process {
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("helpers/wallpaper-events.py").toString().replace(/^file:\/\//, ""))]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") watcher.eventsReady = true;
                if (line === "change" || line === "ready") eventDelay.restart();
            }
        }
        stderr: StdioCollector {}
        onExited: {
            watcher.eventsReady = false;
            eventRestart.start();
        }
    }
    readonly property Timer eventRestart: Timer {
        interval: 30000
        onTriggered: watcher.events.running = true
    }
    readonly property Timer eventDelay: Timer {
        interval: 100
        onTriggered: watcher.requestQuery()
    }
    readonly property Connections outputs: Connections {
        target: Quickshell
        function onScreensChanged() { eventDelay.restart(); }
    }
    function acceptQuery(text) {
        let next = Query.sources(text);
        if (JSON.stringify(next) !== JSON.stringify(sources)) sources = next;
    }
    readonly property Process query: Process {
        command: ["awww", "query"]
        running: true
        environment: ({LC_ALL: "C"})
        onRunningChanged: if (running) watcher.response = ""
        stdout: StdioCollector { onStreamFinished: watcher.response = text }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            // A failed/partial query is not a wallpaper change. Keep colors
            // stable during daemon restarts and avoid rapid failed retries.
            if (code === 0) {
                watcher.acceptQuery(watcher.response);
                watcher.retryInterval = 2000;
            } else watcher.retryInterval = Math.min(30000, watcher.retryInterval * 2);
            if (watcher.queryPending) {
                watcher.queryPending = false;
                eventDelay.restart();
            }
            watcher.poll.restart();
        }
    }
    readonly property Timer poll: Timer {
        // Keep a correctness fallback: clear/disabled cache need not write a file.
        interval: watcher.eventsReady && watcher.retryInterval === 2000 ? 30000 : watcher.retryInterval
        running: true; repeat: true
        onTriggered: watcher.requestQuery()
    }
}
