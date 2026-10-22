import QtQuick
import Quickshell.Io

Item {
    id: internet
    property string interfaceName: ""
    property string connectionName: ""
    readonly property string connectionKey: interfaceName ? interfaceName + "\n" + connectionName : ""
    property string connectivity: "unknown"
    readonly property bool warning: connectivity === "offline"
    readonly property string label: connectivity === "online" ? "Internet access"
        : connectivity === "offline" ? "No internet access" : "Checking internet…"
    property string pendingKey: ""
    property string response: ""
    onConnectionKeyChanged: {
        connectivity = "unknown";
        refresh.restart();
    }
    Component.onCompleted: refresh.start()

    function check() {
        if (!connectionKey || probe.running) return;
        pendingKey = connectionKey;
        response = "";
        probe.command = ["curl", "--silent", "--fail", "--noproxy", "*",
            "--interface", interfaceName, "--connect-timeout", "4", "--max-time", "8",
            "--max-filesize", "4096", "http://nmcheck.gnome.org/check_network_status.txt"];
        probe.running = true;
    }
    function acceptResult(key, code, body) {
        // A result from a previous network must never change the current icon.
        if (!connectionKey || key !== connectionKey) return;
        connectivity = code === 0 && body.trim() === "NetworkManager is online" ? "online" : "offline";
    }
    Timer { id: refresh; interval: 100; onTriggered: internet.check() }
    Timer {
        interval: 30000
        running: !!internet.connectionKey
        repeat: true
        onTriggered: internet.check()
    }
    Process {
        id: probe
        objectName: "wifiInternetProbe"
        stdout: StdioCollector { onStreamFinished: internet.response = text }
        stderr: StdioCollector {}
        onExited: code => {
            internet.acceptResult(internet.pendingKey, code, internet.response);
            if (internet.connectionKey && internet.pendingKey !== internet.connectionKey) refresh.restart();
        }
    }
}
