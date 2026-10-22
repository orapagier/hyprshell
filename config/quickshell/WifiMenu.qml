pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    required property var services
    property var selected: null
    property string statusText: ""
    spacing: 8
    Component.onCompleted: services.scanWifi(true)
    Component.onDestruction: services.scanWifi(false)
    Connections {
        target: page.selected
        function onConnectionFailed(reason) { page.statusText = ConnectionFailReason.toString(reason); }
        function onConnectedChanged() { if (page.selected && page.selected.connected) { page.statusText = "Connected to " + page.selected.name; page.selected = null; } }
    }
    MenuLabel { text: page.services.wifiEnabled ? "Available networks" : "Wi-Fi is turned off"; color: page.menuColors.secondary }
    MenuLabel {
        objectName: "wifiInternetStatus"
        text: page.services.statusData.network.internetStatus || ""
        visible: text.length > 0
        color: page.services.statusData.network.internetWarning ? "#f9e2af" : page.menuColors.accent
        Layout.fillWidth: true
    }
    ScrollView {
        id: networkScroll
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(240, networks.implicitHeight)
        visible: page.services.wifiEnabled
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: networks
            width: networkScroll.availableWidth
            spacing: 5
            Repeater {
                model: page.services.wifiNetworks
                delegate: MenuButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    Layout.minimumHeight: 36
                    Layout.preferredHeight: 36
                    Layout.maximumHeight: 36
                    font.family: "GoMono Nerd Font"
                    text: page.services.wifiIcon(modelData.signalStrength) + "  " + modelData.name + (modelData.connected ? "  ✓" : modelData.security !== WifiSecurityType.Open ? "  󰌾" : "")
                    accent: modelData.connected ? page.menuColors.accent : page.menuColors.text
                    enabled: !modelData.stateChanging
                    onClicked: {
                        page.selected = modelData;
                        page.statusText = "";
                        password.text = "";
                        if (modelData.connected) modelData.disconnect();
                        else if (modelData.known || modelData.security === WifiSecurityType.Open || modelData.security === WifiSecurityType.Owe) modelData.connect();
                        else password.forceActiveFocus();
                    }
                }
            }
        }
    }
    ColumnLayout {
        visible: !!page.selected && !page.selected.connected && !page.selected.known && page.selected.security !== WifiSecurityType.Open && page.selected.security !== WifiSecurityType.Owe
        Layout.fillWidth: true
        MenuLabel { text: page.selected ? page.selected.name : ""; color: page.menuColors.accent; Layout.fillWidth: true }
        TextField {
            id: password
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Password"
            color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary; font.pixelSize: 13
            background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#44cdd6f4" }
            onAccepted: connect.clicked()
        }
        MenuButton {
            id: connect
            text: "Connect"; Layout.fillWidth: true
            enabled: !!page.selected && !page.selected.stateChanging
            onClicked: {
                if (!page.selected) return;
                page.statusText = "Connecting…";
                page.selected.connectWithPsk(password.text);
                password.text = "";
            }
        }
    }
    MenuLabel { text: page.statusText; visible: text.length > 0; color: "#f9e2af"; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        MenuButton { text: "Refresh"; Layout.fillWidth: true; enabled: page.services.wifiEnabled; onClicked: { page.services.scanWifi(false); rescan.restart(); } }
        MenuButton { text: page.services.wifiEnabled ? "Wi-Fi off" : "Wi-Fi on"; Layout.fillWidth: true; onClicked: page.services.toggleWifi() }
    }
    Timer { id: rescan; interval: 150; onTriggered: page.services.scanWifi(true) }
}
