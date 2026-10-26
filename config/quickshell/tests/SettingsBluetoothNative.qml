import QtQuick
import Quickshell
import Quickshell.Bluetooth
import ".."

ShellRoot {
    id: test
    property int phase: 0
    QtObject {
        id: radio
        property bool enabled: true
        property bool discoverable: false
        property bool discovering: false
    }
    QtObject {
        id: headphones
        property string name: "Studio headphones"
        property string address: "00:11:22:33:44:55"
        property bool paired: true
        property bool bonded: true
        property bool connected: false
        property bool pairing: false
        property bool trusted: false
        property bool blocked: false
        property bool wakeAllowed: false
        property bool batteryAvailable: true
        property real battery: 0.75
        property int state: connected ? BluetoothDeviceState.Connected : BluetoothDeviceState.Disconnected
        property int connects: 0
        property int disconnects: 0
        property int forgets: 0
        function connect() { connects++; connected = true; }
        function disconnect() { disconnects++; connected = false; }
        function forget() { forgets++; }
    }
    FloatingWindow { visible: true; implicitWidth: 800; implicitHeight: 1200; SettingsBluetooth { id: page; width: parent.width; adapter: radio; devices: [headphones] } }
    function find(object, name, seen) {
        if (!object || seen.indexOf(object) !== -1) return null;
        seen.push(object);
        if (object.objectName === name) return object;
        let children = [];
        if (object.children) for (let child of object.children) children.push(child);
        if (object.data && typeof object.data.length === "number")
            for (let i = 0; i < object.data.length; ++i) children.push(object.data[i]);
        if (object.contentItem) children.push(object.contentItem);
        for (let child of children) { let result = find(child, name, seen); if (result) return result; }
        return null;
    }
    function control(name) { return find(page, name, []); }
    function check(ok, message) { if (!ok) { console.error("BLUETOOTH_FAILED", phase, message); Qt.exit(1); } }
    function toggle(name, value) { let item = control(name); item.checked = value; item.toggled(); }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0) {
                test.check(radio.enabled && !radio.discoverable && !page.pairingOpen, "initial radio state changed");
                test.check(headphones.connects + headphones.disconnects + headphones.forgets === 0, "browsing changed a device");
                test.toggle("bluetoothDiscoverable", true);
                test.check(radio.discoverable, "discoverable switch");
                test.toggle("bluetoothPower", false);
                test.check(!radio.enabled && !test.control("bluetoothPair").enabled, "power off");
                test.toggle("bluetoothPower", true);
                test.phase++;
            } else if (test.phase === 1) {
                test.control("bluetoothConnect0").clicked();
                test.check(headphones.connected && headphones.connects === 1, "connect action");
                test.control("bluetoothConnect0").clicked();
                test.check(!headphones.connected && headphones.disconnects === 1, "disconnect action");
                test.control("bluetoothDetails0").clicked();
                test.toggle("bluetoothTrusted0", true);
                test.toggle("bluetoothWake0", true);
                test.toggle("bluetoothBlocked0", true);
                test.check(headphones.trusted && headphones.wakeAllowed && headphones.blocked, "device preferences");
                test.check(!test.control("bluetoothConnect0").enabled, "blocked device connection");
                test.control("bluetoothForget0").clicked();
                test.check(headphones.forgets === 0, "forgot without confirmation");
                test.phase++;
            } else if (test.phase === 2) {
                test.control("bluetoothForgetCancel").clicked();
                test.check(headphones.forgets === 0 && page.forgetDevice === null, "cancel forget");
                test.control("bluetoothForget0").clicked();
                test.phase++;
            } else if (test.phase === 3) {
                test.control("bluetoothForgetConfirm").clicked();
                test.check(headphones.forgets === 1, "confirm forget");
                test.control("bluetoothPair").clicked();
                test.phase++;
            } else if (test.phase === 4) {
                test.check(page.pairingOpen && radio.discovering, "explicit discovery");
                test.control("bluetoothPair").clicked();
                test.phase++;
            } else if (test.phase === 5) {
                test.check(!radio.discovering && !page.pairingOpen, "discovery cleanup");
                page.adapter = null;
                test.check(!test.control("bluetoothPower").enabled && !test.control("bluetoothPair").enabled, "missing adapter");
                console.log("BLUETOOTH_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("BLUETOOTH_TIMEOUT", test.phase); Qt.exit(2); } }
}
