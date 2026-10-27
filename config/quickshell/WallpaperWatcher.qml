import QtQuick
import Quickshell.Io
import "WallpaperQuery.js" as Query

QtObject {
    id: watcher
    property var sources: ({})
    property string response: ""
    property int retryInterval: 2000
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
        }
    }
    readonly property Timer poll: Timer {
        interval: watcher.retryInterval; running: true; repeat: true
        onTriggered: if (!watcher.query.running) watcher.query.running = true
    }
}
