pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "AdaptiveColors.js" as Colors

ColumnLayout {
    id: page
    required property var services
    readonly property var menuColors: Colors.menuColorsFor(page)
    property var info: ({})
    property string message: ""
    property string pendingPassword: ""
    property string pendingOperation: "hotspot-status"
    property bool nameEdited: false
    property bool success: true
    readonly property bool busy: worker.running
    readonly property bool active: !!page.info.hotspot
    spacing: 8

    function request(payload, password) {
        if (busy) return;
        page.message = "";
        page.pendingOperation = payload.operation || "";
        page.pendingPassword = password || "";
        worker.stdinEnabled = page.pendingPassword.length > 0;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/network.py").toString().replace(/^file:\/\//, "")),
                          "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function refresh() { request({operation: "hotspot-status"}) }
    function applySavedSsid() {
        if (!page.active && !page.nameEdited)
            ssid.text = page.info.saved?.ssid || "";
    }
    Component.onCompleted: refresh()

    Process {
        id: worker
        onStarted: {
            if (page.pendingPassword) {
                worker.write(page.pendingPassword + "\n");
                page.pendingPassword = "";
            }
        }
        onExited: code => { if (code !== 0 && !page.message) { page.success = false; page.message = "Network helper failed. Refresh and try again."; } }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok !== false;
                    page.info = result;
                    page.message = result.message || (page.success ? "" : "Could not read NetworkManager status.");
                    if (page.success && page.pendingOperation !== "hotspot-status") page.nameEdited = false;
                    page.applySavedSsid();
                } catch (error) {
                    page.success = false;
                    page.info = {};
                    page.message = "Could not read NetworkManager status.";
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text && !page.message) { page.success = false; page.message = "Network helper failed. Refresh and try again."; } }
    }

    MenuLabel {
        objectName: "hotspotStatus"
        text: page.active ? "Hotspot active" : "Hotspot off"
        color: page.active ? page.menuColors.accent : page.menuColors.secondary
        Layout.fillWidth: true
    }
    MenuLabel {
        objectName: "hotspotDetails"
        visible: page.active
        text: {
            let hotspot = page.info.hotspot;
            return hotspot ? "SSID: " + hotspot.ssid + "\nDevice: " + hotspot.device : "";
        }
        color: page.menuColors.text
        Layout.fillWidth: true
    }
    MenuLabel {
        text: page.info.sources && page.info.sources.length ? "Shares: " + page.info.sources.join(", ")
            : "Connect to Wi-Fi or Ethernet to share it."
        color: page.menuColors.secondary
        visible: !page.active
        Layout.fillWidth: true
    }
    TextField {
        id: ssid
        objectName: "hotspotName"
        visible: !page.active
        Layout.fillWidth: true
        echoMode: TextInput.Normal
        placeholderText: "Network name (uses saved name when blank)"
        color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary; font.pixelSize: 13
        background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#44cdd6f4" }
        onTextEdited: page.nameEdited = true
        onAccepted: start.clicked()
    }
    TextField {
        id: password
        objectName: "hotspotPassword"
        visible: !page.active
        Layout.fillWidth: true
        echoMode: TextInput.Password
        placeholderText: "New password (blank keeps saved one)"
        color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary; font.pixelSize: 13
        background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#44cdd6f4" }
        onAccepted: start.clicked()
    }
    MenuLabel {
        objectName: "hotspotMessage"
        text: page.message
        visible: text.length > 0
        color: page.success ? page.menuColors.accent : "#f38ba8"
        Layout.fillWidth: true
    }
    RowLayout {
        Layout.fillWidth: true
        MenuButton {
            id: start
            objectName: page.active ? "hotspotStop" : "hotspotStart"
            text: page.busy ? "Working…" : page.active ? "Stop hotspot" : "Start hotspot"
            Layout.fillWidth: true
            enabled: !page.busy && (!page.active || !!page.info.hotspot?.uuid)
            onClicked: {
                if (page.active) {
                    page.request({operation: "hotspot-stop", uuid: page.info.hotspot.uuid});
                } else if (!page.busy) {
                    let payload = {operation: "hotspot-start", ssid: ssid.text};
                    let entered = password.text;
                    if (entered) payload.passwordViaStdin = true;
                    password.text = "";
                    page.request(payload, entered);
                }
            }
        }
        MenuButton {
            objectName: "hotspotSave"
            text: "Save settings"
            visible: !page.active
            Layout.fillWidth: true
            enabled: !page.busy
            onClicked: {
                let payload = {operation: "hotspot-save", ssid: ssid.text};
                let entered = password.text;
                if (entered) payload.passwordViaStdin = true;
                password.text = "";
                page.request(payload, entered);
            }
        }
        MenuButton {
            objectName: "hotspotRefresh"
            text: "Refresh"
            Layout.fillWidth: true
            enabled: !page.busy
            onClicked: page.refresh()
        }
    }
    RowLayout {
        visible: !page.active && page.info.wifiEnabled === false
        Layout.fillWidth: true
        MenuButton {
            text: "Turn Wi-Fi on"
            Layout.fillWidth: true
            onClicked: page.services.toggleWifi()
        }
    }
    MenuLabel {
        text: "NetworkManager shares the active Ethernet or Wi-Fi connection and saves your hotspot name and password. Leave the password blank to reuse the saved one; a new password goes through stdin, never Hyprshell settings or arguments."
        color: page.menuColors.secondary
        Layout.fillWidth: true
    }
}
