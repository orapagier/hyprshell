pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: view
    property var readings: ({})
    property var battery: ({})
    property string connection: "Offline"
    property string bluetooth: "Unavailable"
    property url wallpaperSource: ""
    property real screenWidth: 1920
    property real screenHeight: 1080
    property real originX: 0
    property real originY: 0
    implicitHeight: 620
    readonly property real unit: Math.max(12, Math.min(18, (height - 36) / 32))
    function value(key) { return readings[key] ?? "—"; }
    function bytes(n) {
        if (n === undefined || n === null) return "—";
        let units = ["B", "KiB", "MiB", "GiB", "TiB"], i = 0;
        while (n >= 1024 && i < units.length - 1) { n /= 1024; ++i; }
        return n.toFixed(i > 1 ? 1 : 0) + " " + units[i];
    }
    function duration(seconds) {
        if (seconds === undefined) return "—";
        let minutes = Math.floor(seconds / 60);
        return Math.floor(minutes / 1440) + "d " + Math.floor(minutes / 60) % 24 + "h " + minutes % 60 + "m";
    }
    readonly property var sections: [
        {title: "SYSTEM", rows: [value("os"), value("model"), "Kernel  " + value("kernel"),
            "OS age  " + (readings.install_epoch ? "~" + Math.max(0, Math.floor((Date.now()/1000 - readings.install_epoch)/86400)) + " days · " + Qt.formatDate(new Date(readings.install_epoch*1000), "dd MMM yyyy") : "Unknown"),
            "Uptime  " + duration(readings.uptime), "Display  " + screenWidth + " × " + screenHeight]},
        {title: "PROCESSOR", rows: [value("cpu_model"), value("cpu_topology"),
            "Usage  " + value("cpu_percent") + "%   ·   " + value("frequency"),
            "Load  " + value("load") + "   ·   " + value("tasks") + " tasks",
            "Thermals  " + value("temperature"), "Graphics  " + value("gpu")]},
        {title: "MEMORY & STORAGE", rows: ["RAM  " + bytes(readings.memory_used) + " / " + bytes(readings.memory_total),
            "Available  " + bytes(readings.memory_available) + "   ·   Cache  " + bytes(readings.memory_cache),
            "Swap  " + bytes(readings.swap_used) + " / " + bytes(readings.swap_total),
            "Root  " + value("root_usage"), "Home  " + value("home_usage"),
            "Disk I/O  ↓ " + bytes(readings.disk_read_rate) + "/s  ↑ " + bytes(readings.disk_write_rate) + "/s"]},
        {title: "NETWORK & POWER", rows: [connection.split("\n")[0],
            "Traffic  ↓ " + bytes(readings.rx_rate) + "/s  ↑ " + bytes(readings.tx_rate) + "/s",
            "Link totals  ↓ " + bytes(readings.rx_total) + "  ↑ " + bytes(readings.tx_total),
            "Bluetooth  " + bluetooth.split("\n")[0].replace(/^Bluetooth · /, ""),
            battery.present ? "Battery  " + battery.percentage + "% · " + battery.status : "Power  AC / battery unavailable",
            battery.present ? "Draw  " + (battery.power === null || battery.power === undefined ? "—" : Number(battery.power).toFixed(1) + " W") + "   ·   Health  " + (battery.health === null || battery.health === undefined ? "—" : Math.round(battery.health) + "%") : ""]}
    ]
    WallpaperColors {
        id: sampler
        source: view.wallpaperSource
        screenWidth: view.screenWidth; screenHeight: view.screenHeight
        offsetX: view.originX; regionOffsetX: view.originX; offsetY: view.originY
        bandWidth: view.width; bandHeight: view.height
    }
    Column {
        id: content
        width: parent.width
        spacing: 8
        Repeater {
            model: ["SYSTEM", "PROCESSOR", "MEMORY & STORAGE", "NETWORK & POWER"]
            delegate: Item {
                id: section
                required property string modelData
                required property int index
                readonly property var rows: view.sections[index].rows.filter(s => s.length > 0)
                width: content.width
                implicitHeight: lines.implicitHeight
                readonly property var palette: sampler.paletteFor(section, view, Qt.color("#cdd6f4"), "bare-normal")
                Column {
                    id: lines
                    width: parent.width
                    Text {
                        text: section.modelData
                        font { family: "DejaVu Sans"; pixelSize: view.unit * 0.72; bold: true; letterSpacing: 2 }
                        height: view.unit + 3
                        color: section.palette.foreground
                        style: section.palette.glyphHalo ? Text.Outline : Text.Normal
                        styleColor: section.palette.glyphOutline || "#080a0d"
                        textFormat: Text.PlainText
                    }
                    Repeater {
                        model: section.rows.length
                        delegate: Text {
                            required property int index
                            width: lines.width
                            height: view.unit
                            text: section.rows[index]
                            elide: Text.ElideRight
                            font { family: "DejaVu Sans"; pixelSize: view.unit * 0.72 }
                            color: section.palette.foreground
                            style: section.palette.glyphHalo ? Text.Outline : Text.Normal
                            styleColor: section.palette.glyphOutline || "#080a0d"
                            textFormat: Text.PlainText
                        }
                    }
                }
            }
        }
        Text {
            width: parent.width
            text: "3 s refresh · OS age: filesystem creation estimate"
            font { family: "DejaVu Sans"; pixelSize: Math.max(9, view.unit * 0.6) }
            readonly property var palette: sampler.paletteFor(this, view, Qt.color("#cdd6f4"), "bare-normal")
            color: palette.foreground
            style: palette.glyphHalo ? Text.Outline : Text.Normal
            styleColor: palette.glyphOutline || "#080a0d"
            textFormat: Text.PlainText
        }
    }
}
