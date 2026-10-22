import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: root
    property var testServices: services
    property int phase: 0
    function compare(actual, expected) {
        if (actual !== expected) throw new Error("Expected " + expected + "; got " + actual);
    }
    function findChild(object, name) { return object.findChild ? object.findChild(name) : find(object, name); }
    function find(object, name) {
        if (object.objectName === name) return object;
        for (let child of object.children || []) { let result = find(child, name); if (result) return result; }
        return null;
    }
    WifiInternet { id: internet }
    Bar { id: bar; width: 600 }
    QtObject {
        id: services
        property bool wifiEnabled: true
        property var wifiNetworks: []
        property var statusData: bar.statusData
        function scanWifi(enabled) {}
    }
    WifiMenu { id: menu; y: 50; width: 280; services: root.testServices }
    Item {
        id: cases
        function init() { internet.interfaceName = "wlan-test"; internet.connectionName = "Test"; }
        function cleanup() { internet.interfaceName = ""; }
        function test_probeResults_data() {
            return [
                {tag: "online", code: 0, body: "NetworkManager is online\n", state: "online"},
                {tag: "timeout", code: 28, body: "", state: "offline"},
                {tag: "dns-failure", code: 6, body: "", state: "offline"},
                {tag: "captive-portal", code: 0, body: "<html>Sign in</html>", state: "offline"},
                {tag: "redirect", code: 0, body: "", state: "offline"},
                {tag: "error-with-online-body", code: 22, body: "NetworkManager is online", state: "offline"}
            ];
        }
        function test_probeResults(data) {
            internet.acceptResult(internet.connectionKey, data.code, data.body);
            compare(internet.connectivity, data.state);
            compare(internet.warning, data.state === "offline");
        }
        function test_networkChangeRejectsStaleResult() {
            let oldKey = internet.connectionKey;
            internet.acceptResult(oldKey, 0, "NetworkManager is online");
            internet.connectionName = "Another Wi-Fi";
            compare(internet.connectivity, "unknown");
            internet.acceptResult(oldKey, 28, "");
            compare(internet.connectivity, "unknown");
            internet.interfaceName = "";
            internet.acceptResult(oldKey, 0, "NetworkManager is online");
            compare(internet.connectivity, "unknown");
        }
        function test_iconAndMenuUpdateAcrossLayouts() {
            let trigger = findChild(bar, "wifiTrigger");
            let label = findChild(menu, "wifiInternetStatus");
            for (let edge of ["top", "bottom", "left", "right"]) {
                bar.settings = {bar:{position:edge}};
                for (let compact of [false, true]) {
                    bar.statusIconsOnly = compact;
                    for (let warning of [false, true]) {
                        bar.statusData = {workspaces:[], audio:{}, bluetooth:{}, battery:{},
                            network:{text:warning ? "󰤩" : "󰤨", connected:true, internetWarning:warning,
                                internetStatus:warning ? "No internet access" : "Internet access"}};
                        compare(trigger.text, warning ? "󰤩" : "󰤨");
                        compare(trigger.compactIcon, trigger.text);
                        compare(trigger.foreground.toString(), warning ? "#f9e2af" : "#94e2d5");
                        compare(label.text, warning ? "No internet access" : "Internet access");
                    }
                }
            }
            bar.statusData = {workspaces:[], audio:{}, bluetooth:{}, battery:{}, network:{text:"󰤮", connected:false}};
            compare(trigger.foreground.toString(), "#585b70");
            compare(label.visible, false);
        }
    }
    Component.onCompleted: {
        try {
            cases.init();
            for (let row of cases.test_probeResults_data()) cases.test_probeResults(row);
            cases.test_networkChangeRejectsStaleResult();
            cases.test_iconAndMenuUpdateAcrossLayouts();
            internet.interfaceName = "test-online";
            internet.connectionName = "Native pipeline";
        } catch (error) { console.error("WIFI_FAIL", error); Qt.quit(); }
    }
    Timer {
        interval: 450; running: true; repeat: true
        onTriggered: {
            try {
                if (root.phase === 0) {
                    root.compare(internet.connectivity, "online");
                    internet.interfaceName = "test-offline";
                } else if (root.phase === 1) {
                    root.compare(internet.connectivity, "offline");
                    internet.interfaceName = "test-portal";
                } else if (root.phase === 2) {
                    root.compare(internet.connectivity, "offline");
                    internet.interfaceName = "test-online";
                } else {
                    root.compare(internet.connectivity, "online");
                    internet.interfaceName = "";
                    root.compare(internet.connectivity, "unknown");
                    console.log("WIFI_PASS: connectivity, recovery, stale results, all panel edges, compact icons and menu");
                    Qt.quit();
                }
                root.phase++;
            } catch (error) { console.error("WIFI_FAIL", error); Qt.quit(); }
        }
    }
}
