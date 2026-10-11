pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "SettingsStyle.js" as Style

ColumnLayout {
    id: page
    property var profiles: []
    property string connectivity: "unknown"
    property bool editorAvailable: false
    property bool loaded: false
    property bool success: true
    property string message: ""
    property string query: ""
    property var pendingForget: null
    readonly property bool busy: worker.running
    readonly property var filtered: profiles.filter(row => (row.name + " " + typeName(row.type)).toLowerCase().includes(query.trim().toLowerCase()))
    spacing: 16
    Component.onCompleted: if (visible) request({operation: "status"})
    onVisibleChanged: {
        pendingForget = null;
        if (visible && !busy) request({operation: "status"});
    }
    function typeName(kind) {
        return ({"802-11-wireless": "Wi-Fi", "802-3-ethernet": "Ethernet", vpn: "VPN", wireguard: "WireGuard", loopback: "Loopback"})[kind] || kind;
    }
    function request(payload) {
        if (busy) return;
        pendingForget = null;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/network.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function change(operation, row) {
        request({operation: operation, uuid: row.uuid, expected: row.revision, confirmed: operation === "forget"});
    }
    Process {
        id: worker
        onExited: (code, status) => { if (code !== 0) { page.success = false; page.message = "Network helper failed. Refresh and try again."; } }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    page.message = result.message || "";
                    if (result.ok && result.profiles !== undefined) {
                        page.profiles = result.profiles;
                        page.connectivity = result.connectivity;
                        page.editorAvailable = result.editor;
                        page.loaded = true;
                    }
                } catch (e) { page.success = false; page.message = "Could not read network status. Refresh and try again."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = "Network helper failed. Refresh and try again."; } }
    }
    Label { objectName: "networkMessage"; visible: !!page.message; text: page.message; color: page.success ? Style.success : Style.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    RowLayout {
        Layout.fillWidth: true
        SettingsButton { objectName: "refreshNetwork"; text: page.busy ? "Working…" : "Refresh"; enabled: !page.busy; onClicked: page.request({operation: "status"}) }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Style.muted
            text: !page.loaded ? "Network status has not been read." : ({full: "Internet access available", portal: "Sign in to this network to access the internet", limited: "Connected with limited internet access", none: "Disconnected", unknown: "Internet access has not been determined"})[page.connectivity] || "Internet access has not been determined"
        }
    }
    SettingsCard {
        title: "Saved connections"
        subtitle: "Connect opens a terminal for passwords and connection results. Edit includes automatic connection, IP addresses, DNS, and security. Refresh after using another network tool."
        Layout.fillWidth: true
        TextField { objectName: "networkSearch"; Layout.fillWidth: true; placeholderText: "Find a connection or type"; color: Style.text; selectByMouse: true; onTextChanged: page.query = text }
        Label { visible: page.loaded && page.filtered.length === 0; text: page.profiles.length ? "No matching connections." : "No saved connections. Use the Wi-Fi menu or add one below."; color: Style.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Repeater {
            model: page.filtered
            delegate: ColumnLayout {
                id: connection
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Label { Layout.fillWidth: true; text: connection.modelData.name; color: Style.text; font.bold: true; wrapMode: Text.Wrap }
                Label { Layout.fillWidth: true; text: page.typeName(connection.modelData.type) + (connection.modelData.active ? " · Active" : " · Disconnected"); color: connection.modelData.active ? Style.success : Style.muted; wrapMode: Text.Wrap }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    SettingsButton { objectName: "connectNetwork-" + connection.modelData.uuid; text: connection.modelData.active ? "Disconnect" : "Connect…"; enabled: !page.busy; onClicked: page.change(connection.modelData.active ? "disconnect" : "connect", connection.modelData) }
                    SettingsButton { text: "Edit…"; enabled: !page.busy && page.editorAvailable; onClicked: page.change("edit", connection.modelData) }
                    SettingsButton { objectName: "forgetNetwork-" + connection.modelData.uuid; text: "Forget…"; enabled: !page.busy && !connection.modelData.active; onClicked: page.pendingForget = connection.modelData }
                }
            }
        }
        Label { visible: page.pendingForget !== null; text: page.pendingForget ? "Forget “" + page.pendingForget.name + "”? This removes its saved settings and credentials. You will need to add it again." : ""; color: Style.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
        RowLayout {
            visible: page.pendingForget !== null
            SettingsButton { objectName: "confirmForgetNetwork"; text: "Forget connection"; enabled: !page.busy && page.pendingForget !== null; onClicked: page.change("forget", page.pendingForget) }
            SettingsButton { objectName: "cancelForgetNetwork"; text: "Cancel"; enabled: !page.busy; onClicked: page.pendingForget = null }
        }
    }
    SettingsCard {
        title: "Hidden Wi-Fi"
        subtitle: "Enter the exact network name. The connection terminal asks for its password and shows the result."
        Layout.fillWidth: true
        TextField { id: hiddenName; objectName: "hiddenNetworkName"; Layout.fillWidth: true; placeholderText: "Network name (SSID)"; color: Style.text; selectByMouse: true; enabled: !page.busy }
        SettingsButton { objectName: "connectHiddenNetwork"; text: "Connect hidden Wi-Fi…"; enabled: !page.busy && hiddenName.text.length > 0; onClicked: page.request({operation: "hidden", ssid: hiddenName.text}) }
        Label { text: "For enterprise networks, configure authentication and certificates with Add Wi-Fi first, then connect the saved profile above."; color: Style.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
    SettingsCard {
        title: "Add or configure a connection"
        subtitle: "Enterprise Wi-Fi: choose WPA/WPA2 Enterprise and enter your organization’s authentication and certificate settings."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true
            spacing: 8
            SettingsButton { objectName: "addWifiNetwork"; text: "Add Wi-Fi…"; enabled: !page.busy && page.editorAvailable; onClicked: page.request({operation: "create", type: "802-11-wireless"}) }
            SettingsButton { text: "Add Ethernet…"; enabled: !page.busy && page.editorAvailable; onClicked: page.request({operation: "create", type: "802-3-ethernet"}) }
            SettingsButton { objectName: "addVpnNetwork"; text: "Add VPN…"; enabled: !page.busy && page.editorAvailable; onClicked: page.request({operation: "create", type: "vpn"}) }
            SettingsButton { objectName: "addWireguardNetwork"; text: "Add WireGuard…"; enabled: !page.busy && page.editorAvailable; onClicked: page.request({operation: "create", type: "wireguard"}) }
        }
        SettingsButton { text: "Advanced connection settings…"; enabled: !page.busy && page.editorAvailable; onClicked: page.request({operation: "editor"}) }
        Label { visible: page.loaded && !page.editorAvailable; text: "Install nm-connection-editor to add or edit connections."; color: Style.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { text: "VPN setup and file import use the editor’s connection chooser. Provider-specific VPNs need their NetworkManager plugin; WireGuard uses NetworkManager’s built-in support. Network credentials stay on this laptop and are excluded from GitHub configuration sync."; color: Style.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
}
