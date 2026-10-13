pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import "AudioStatus.js" as AudioStatus

Item {
    id: services
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var microphone: Pipewire.defaultAudioSource
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var applicationStreams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.ready)
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
    readonly property var workspaceData: spaces.map(w => ({id: w.id, name: w.name, active: w.active, monitor: w.monitor ? w.monitor.name : ""}))
    readonly property var wifiDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property var wifiNetworks: {
        let found = [];
        for (let device of wifiDevices) found = found.concat(device.networks.values);
        return found.sort((a,b) => Number(b.connected) - Number(a.connected) || b.signalStrength - a.signalStrength);
    }
    readonly property var connectedWifi: wifiNetworks.find(n => n.connected) || null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDevices: Bluetooth.devices.values.slice().sort((a,b) => Number(b.connected) - Number(a.connected) || Number(b.paired) - Number(a.paired) || a.name.localeCompare(b.name))
    readonly property var connectedBluetooth: bluetoothDevices.filter(d => d.connected)
    AudioRoute { id: audioRoute; sink: services.sink; bluetoothDevices: services.connectedBluetooth }
    readonly property string audioIcon: AudioStatus.icon(audioRoute.headset, !!(sink && sink.audio && sink.audio.muted), sink && sink.audio ? sink.audio.volume : 0)
    readonly property var battery: UPower.displayDevice
    readonly property int capacity: battery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: battery && battery.state === UPowerDeviceState.Charging
    readonly property var batteryDetails: UPower.devices.values.find(d => d.isLaptopBattery && d.isPresent) || battery
    BatteryCapacityReader {
        id: batteryCapacity
        nativePath: services.batteryDetails ? services.batteryDetails.nativePath : ""
    }
    readonly property var batteryInfo: ({
        present: !!(battery && battery.isPresent && battery.isLaptopBattery),
        percentage: capacity,
        status: battery ? UPowerDeviceState.toString(battery.state) : "Unavailable",
        charging: charging,
        pluggedIn: !UPower.onBattery,
        discharging: !!(battery && battery.state === UPowerDeviceState.Discharging),
        seconds: battery ? charging ? battery.timeToFull : battery.timeToEmpty : 0,
        // UPower health is already 0–100; charge percentage is a 0–1 fraction.
        health: batteryDetails && batteryDetails.healthSupported ? batteryDetails.healthPercentage : null,
        power: battery ? battery.changeRate : null,
        energy: battery ? battery.energy : null,
        energyCapacity: battery ? battery.energyCapacity : null,
        fullMah: batteryCapacity.fullMah,
        designMah: batteryCapacity.designMah,
        model: batteryDetails ? batteryDetails.model : ""
    })
    BatteryAlert {
        id: batteryAlert
        info: services.batteryInfo
        onTriggered: {
            if (!batteryAlertSound.running) batteryAlertSound.running = true;
        }
    }
    Process {
        id: batteryAlertSound
        command: ["paplay", "--volume=49152", "--client-name=Hyprshell", "--stream-name=Low battery alert",
                  decodeURIComponent(Qt.resolvedUrl("sounds/test.wav").toString().replace(/^file:\/\//, ""))]
        onExited: (code, status) => {
            if (code !== 0) console.warn("Low battery alert sound could not be played.");
        }
    }
    readonly property var batteryIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    readonly property var statusData: ({
        workspaces: workspaceData,
        audio: {icon: audioIcon, text: sink && sink.audio ? sink.audio.muted ? "muted" : Math.round(sink.audio.volume * 100) + "%" : "--", tooltip: sink ? sink.description : "Audio unavailable"},
        network: {text: connectedWifi ? wifiIcon(connectedWifi.signalStrength) : wired ? "󰈀" : wifiEnabled ? "󰤮" : "󰤭", connected: !!(connectedWifi || wired), tooltip: connectedWifi ? connectedWifi.name + " · " + Math.round(connectedWifi.signalStrength * 100) + "%" : wired ? "Ethernet · " + wired.name : wifiEnabled ? "Offline" : "Wi-Fi turned off"},
        bluetooth: {text: connectedBluetooth.length ? "󰂱" : adapter && adapter.enabled ? "󰂯" : "󰂲", powered: !!(adapter && adapter.enabled), connected: connectedBluetooth.length > 0, tooltip: connectedBluetooth.length ? "Bluetooth · " + connectedBluetooth.length + " connected\n" + connectedBluetooth.map(d => d.name).join("\n") : adapter ? "Bluetooth · " + (adapter.enabled ? "on" : "off") : "Bluetooth is unavailable"},
        battery: {present: !!(battery && battery.isPresent && battery.isLaptopBattery), text: (battery && battery.state === UPowerDeviceState.FullyCharged ? "󰂅" : (charging ? chargingIcons : batteryIcons)[Math.max(0, Math.min(9, Math.floor(capacity * 10 / 101)))]) + " " + capacity + "%", charging: charging, low: batteryAlert.low, warning: capacity <= 30, tooltip: capacity + "% · " + (battery ? UPowerDeviceState.toString(battery.state) : "Unavailable")}
    })
    function wifiIcon(strength) { return ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, Math.floor(Math.max(0, strength) * 5))]; }
    function workspace(id) { let w = spaces.find(w => w.id === Number(id)); if (w) w.activate(); }
    function scrollWorkspace(direction) {
        let step = Number(direction) < 0 ? "-1" : "+1";
        Hyprland.dispatch(Hyprland.usingLua ? 'hl.dsp.focus({ workspace = "e' + step + '" })' : "workspace e" + step);
    }
    function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled; }
    function scanWifi(enabled) { for (let device of wifiDevices) device.scannerEnabled = enabled; }
    function setOutput(node) { Pipewire.preferredDefaultAudioSink = node; }
    function setInput(node) { Pipewire.preferredDefaultAudioSource = node; }
    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => !!n.audio) }
    // This monitors speaker output; it never records the microphone.
    PwNodePeakMonitor { id: meter; node: services.sink; enabled: !!services.sink }
    PwNodeLinkTracker { id: outputLinks; node: services.sink }
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || null
    readonly property var audioStreams: outputLinks.linkGroups.filter(g => g.state === PwLinkState.Active && g.source && g.source.isStream).map(g => g.source)
    readonly property var stream: audioStreams.length ? audioStreams[audioStreams.length - 1] : null
    readonly property string fullTitle: player ? [player.trackArtist, player.trackTitle || player.identity].filter(Boolean).join(" — ") : stream ? (stream.properties["media.name"] || stream.properties["application.name"] || stream.description || "Audio playing") : "Audio playing"
    property real soundedAt: 0
    property real now: Date.now()
    readonly property bool playing: !!player || (!!stream && now - soundedAt < 900)
    AudioSpectrum {
        id: spectrum
        sinkName: services.sink ? services.sink.name : ""
        enabled: services.playing
    }
    property string marqueeKey: ""
    property real marqueeStarted: 0
    property string marquee: ""
    readonly property var mediaData: ({playing: playing, levels: spectrum.levels, title: marquee, tooltip: fullTitle})
    Timer {
        interval: 67; running: true; repeat: true
        onTriggered: {
            services.now = Date.now();
            let peak = meter.peak;
            if (peak > 0.00015) services.soundedAt = services.now;
            if (!services.playing) { services.marquee = ""; services.marqueeKey = ""; return; }
            let title = services.fullTitle;
            if (services.marqueeKey !== title) { services.marqueeKey = title; services.marqueeStarted = services.now; }
            let chars = Array.from(title);
            if (chars.length <= 28) { services.marquee = title; return; }
            let ring = chars.concat(Array.from("   •   "));
            let elapsed = ((services.now - services.marqueeStarted) / 1000) % (2 + ring.length * 0.3);
            let offset = elapsed < 2 ? 0 : Math.floor((elapsed - 2) / 0.3);
            services.marquee = Array.from({length: 28}, (_,i) => ring[(offset+i) % ring.length]).join("");
        }
    }
}
