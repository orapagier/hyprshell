pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Bluetooth
import "style" as Style

ColumnLayout {
    id: page
    // Injectable service boundary also keeps tests independent of real radios.
    property var adapter: Bluetooth.defaultAdapter
    property var devices: adapter ? adapter.devices.values : []
    readonly property bool powered: !!adapter && adapter.enabled
    property bool pairingOpen: false
    property var forgetDevice: null
    readonly property var savedDevices: devices.filter(device => device.paired || device.bonded)
        .sort((a, b) => Number(b.connected) - Number(a.connected) || a.name.localeCompare(b.name))
    onPoweredChanged: if (!powered) pairingOpen = false
    spacing: 24

    SettingsCard {
        title: "Connection"
        Layout.fillWidth: true
        SettingsRow {
            title: "Bluetooth"
            description: !page.adapter ? "No Bluetooth adapter is available." : page.powered ? "Ready to connect your devices." : "Turn on to connect wireless devices."
            SettingsSwitch {
                objectName: "bluetoothPower"
                Layout.alignment: Qt.AlignRight
                Layout.fillWidth: true
                Accessible.name: "Bluetooth power"
                enabled: !!page.adapter
                checked: page.powered
                onToggled: page.adapter.enabled = checked
            }
        }
        SettingsRow {
            title: "Visible to nearby devices"
            description: "Allow other devices to find this computer."
            separator: false
            SettingsSwitch {
                objectName: "bluetoothDiscoverable"
                Layout.alignment: Qt.AlignRight
                Layout.fillWidth: true
                Accessible.name: "Visible to nearby devices"
                enabled: page.powered
                checked: !!page.adapter && page.adapter.discoverable
                onToggled: page.adapter.discoverable = checked
            }
        }
    }
    SettingsCard {
        title: "Your devices"
        subtitle: "Connected devices appear first."
        Layout.fillWidth: true
        Label {
            visible: page.savedDevices.length === 0
            Layout.fillWidth: true
            text: "No paired devices yet. Add headphones, a keyboard, or another device below."
            wrapMode: Text.WordWrap
            font.pixelSize: Style.SettingsTheme.bodySize
            color: Style.SettingsTheme.muted
        }
        Repeater {
            model: page.savedDevices
            delegate: ColumnLayout {
                id: deviceRow
                required property var modelData
                required property int index
                property bool detailsOpen: false
                Layout.fillWidth: true
                spacing: 12
                SettingsRow {
                    title: deviceRow.modelData.name || deviceRow.modelData.address
                    description: BluetoothDeviceState.toString(deviceRow.modelData.state)
                        + (deviceRow.modelData.batteryAvailable ? " · " + Math.round(deviceRow.modelData.battery * 100) + "% battery" : "")
                    separator: false
                    SettingsButton {
                        objectName: "bluetoothConnect" + deviceRow.index
                        text: deviceRow.modelData.connected ? "Disconnect" : "Connect"
                        enabled: page.powered && !deviceRow.modelData.blocked && !deviceRow.modelData.pairing
                            && deviceRow.modelData.state !== BluetoothDeviceState.Connecting
                            && deviceRow.modelData.state !== BluetoothDeviceState.Disconnecting
                        onClicked: deviceRow.modelData.connected ? deviceRow.modelData.disconnect() : deviceRow.modelData.connect()
                    }
                    SettingsButton {
                        objectName: "bluetoothDetails" + deviceRow.index
                        text: deviceRow.detailsOpen ? "Less" : "Details"
                        flat: true
                        onClicked: deviceRow.detailsOpen = !deviceRow.detailsOpen
                    }
                }
                ColumnLayout {
                    visible: deviceRow.detailsOpen
                    Layout.fillWidth: true
                    spacing: 12
                    SettingsSwitch {
                        objectName: "bluetoothTrusted" + deviceRow.index
                        Layout.fillWidth: true
                        text: "Trust this device"
                        checked: deviceRow.modelData.trusted
                        enabled: page.powered
                        onToggled: deviceRow.modelData.trusted = checked
                    }
                    SettingsSwitch {
                        objectName: "bluetoothWake" + deviceRow.index
                        Layout.fillWidth: true
                        text: "Allow this device to wake the computer"
                        checked: deviceRow.modelData.wakeAllowed
                        enabled: page.powered
                        onToggled: deviceRow.modelData.wakeAllowed = checked
                    }
                    SettingsSwitch {
                        objectName: "bluetoothBlocked" + deviceRow.index
                        Layout.fillWidth: true
                        text: "Block connections from this device"
                        checked: deviceRow.modelData.blocked
                        enabled: page.powered
                        onToggled: deviceRow.modelData.blocked = checked
                    }
                    SettingsButton {
                        objectName: "bluetoothForget" + deviceRow.index
                        text: "Forget device…"
                        enabled: page.powered
                        onClicked: { page.forgetDevice = deviceRow.modelData; forgetDialog.open(); }
                    }
                }
                Rectangle {
                    visible: deviceRow.index < page.savedDevices.length - 1
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Style.SettingsTheme.separator
                }
            }
        }
    }
    SettingsCard {
        title: "Add a device"
        subtitle: "Put your device in pairing mode, then search nearby."
        Layout.fillWidth: true
        SettingsButton {
            objectName: "bluetoothPair"
            text: page.pairingOpen ? "Done" : "Find a device"
            highlighted: !page.pairingOpen
            enabled: page.powered
            onClicked: page.pairingOpen = !page.pairingOpen
        }
        // The existing native pairing UI owns the agent, PIN confirmation,
        // bounded scan and cancellation. It only runs after an explicit action.
        Loader {
            Layout.fillWidth: true
            active: page.pairingOpen && page.powered && page.visible
            visible: active
            sourceComponent: BluetoothMenu {
                services: ({adapter: page.adapter, bluetoothDevices: page.devices})
            }
        }
    }
    Popup {
        id: forgetDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(420, parent ? parent.width - 40 : 420)
        padding: 24
        modal: true
        onClosed: page.forgetDevice = null
        background: Rectangle { radius: 16; color: Style.SettingsTheme.surface; border.color: Style.SettingsTheme.border }
        contentItem: ColumnLayout {
            spacing: 18
            Label {
                Layout.fillWidth: true
                text: "Forget " + (page.forgetDevice ? page.forgetDevice.name : "device") + "?"
                font.pixelSize: Style.SettingsTheme.sectionSize; font.weight: Font.DemiBold
                color: Style.SettingsTheme.text; wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: "You’ll need to pair this device again to reconnect."
                color: Style.SettingsTheme.muted; wrapMode: Text.WordWrap
                font.pixelSize: Style.SettingsTheme.bodySize
            }
            RowLayout {
                Layout.fillWidth: true
                SettingsButton { objectName: "bluetoothForgetCancel"; text: "Cancel"; Layout.fillWidth: true; onClicked: forgetDialog.close() }
                SettingsButton {
                    objectName: "bluetoothForgetConfirm"
                    text: "Forget"; Layout.fillWidth: true
                    onClicked: { if (page.forgetDevice) page.forgetDevice.forget(); forgetDialog.close(); }
                }
            }
        }
    }
}
