pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    required property var services
    property string statusText: ""
    property string prompt: ""
    property bool confirmation: false
    property var pairingDevice: null
    property string handledPrompt: ""
    spacing: 8
    function scan() {
        if (services.adapter && services.adapter.enabled) { services.adapter.discovering = true; scanTimeout.restart(); }
    }
    Component.onCompleted: scan()
    Component.onDestruction: {
        if (services.adapter) services.adapter.discovering = false;
        if (pairingDevice && pairingDevice.pairing) pairingDevice.cancelPair();
    }
    Timer { id: scanTimeout; interval: 20000; onTriggered: { if (page.services.adapter) page.services.adapter.discovering = false; } }
    // BlueZ's CLI supplies the pairing agent; all prompts and controls stay in QML.
    Process {
        id: agent
        command: ["bluetoothctl", "--agent", "KeyboardDisplay"]
        environment: ({LC_ALL: "C", TERM: "dumb"})
        running: !!(page.services.adapter && page.services.adapter.enabled)
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: false
            onTextChanged: {
                let clean = text.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
                let tail = clean.slice(-1500);
                let question = tail.match(/(?:\[agent\]\s*)?(Confirm passkey[^\r\n]*|Authorize service[^\r\n]*|Enter (?:PIN code|passkey)[^\r\n]*|Request confirmation[^\r\n]*)/g);
                if (question && question.length && question[question.length - 1] !== page.handledPrompt) { page.prompt = question[question.length - 1]; page.confirmation = /Confirm|Authorize|confirmation/.test(page.prompt); }
                let failure = tail.match(/Failed to (?:pair|connect):[^\r\n]*/g);
                if (failure && failure.length) page.statusText = failure[failure.length - 1];
            }
        }
        onStarted: write("default-agent\n")
    }
    Connections {
        target: page.pairingDevice
        function onPairedChanged() {
            if (page.pairingDevice && page.pairingDevice.paired) { page.pairingDevice.trusted = true; page.pairingDevice.connect(); page.prompt = ""; page.statusText = "Paired"; }
        }
        function onConnectedChanged() { if (page.pairingDevice && page.pairingDevice.connected) { page.statusText = "Connected"; page.prompt = ""; } }
    }
    MenuLabel { text: !page.services.adapter ? "Bluetooth is unavailable" : page.services.adapter.enabled ? page.services.adapter.discovering ? "Scanning…" : "Devices" : "Bluetooth is turned off"; color: page.menuColors.secondary }
    ScrollView {
        id: deviceScroll
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(240, devices.implicitHeight)
        visible: !!(page.services.adapter && page.services.adapter.enabled)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: devices
            width: deviceScroll.availableWidth; spacing: 5
            Repeater {
                model: page.services.bluetoothDevices
                delegate: MenuButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    Layout.minimumHeight: 36
                    Layout.preferredHeight: 36
                    Layout.maximumHeight: 36
                    text: modelData.name + (modelData.connected ? "  ✓" : modelData.pairing ? "  Pairing…" : modelData.paired ? "  Paired" : "")
                    accent: modelData.connected ? page.menuColors.accent : page.menuColors.text
                    onClicked: {
                        page.pairingDevice = modelData;
                        page.statusText = ""; page.prompt = "";
                        if (modelData.connected) modelData.disconnect();
                        else if (modelData.paired) modelData.connect();
                        else modelData.pair();
                    }
                }
            }
        }
    }
    ColumnLayout {
        visible: page.prompt.length > 0; Layout.fillWidth: true
        MenuLabel { text: page.prompt; Layout.fillWidth: true; color: "#f9e2af" }
        TextField {
            id: pin
            visible: !page.confirmation; Layout.fillWidth: true
            placeholderText: "PIN or passkey"; color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary
            background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#44cdd6f4" }
            onAccepted: { page.handledPrompt = page.prompt; agent.write(text + "\n"); text = ""; page.prompt = ""; }
        }
        RowLayout {
            Layout.fillWidth: true
            MenuButton { text: page.confirmation ? "Confirm" : "Send"; Layout.fillWidth: true; onClicked: { page.handledPrompt = page.prompt; agent.write((page.confirmation ? "yes" : pin.text) + "\n"); pin.text = ""; page.prompt = ""; } }
            MenuButton { text: "Cancel"; Layout.fillWidth: true; onClicked: { page.handledPrompt = page.prompt; agent.write("no\n"); if (page.pairingDevice) page.pairingDevice.cancelPair(); page.prompt = ""; } }
        }
    }
    MenuLabel { text: page.statusText; visible: text.length > 0; Layout.fillWidth: true; color: "#f9e2af" }
    RowLayout {
        Layout.fillWidth: true
        MenuButton { text: "Scan"; Layout.fillWidth: true; enabled: !!(page.services.adapter && page.services.adapter.enabled); onClicked: page.scan() }
        MenuButton { text: page.services.adapter && page.services.adapter.enabled ? "Bluetooth off" : "Bluetooth on"; Layout.fillWidth: true; enabled: !!page.services.adapter; onClicked: { page.services.adapter.enabled = !page.services.adapter.enabled; } }
    }
}
