import QtQuick

Canvas {
    id: icon
    property string kind: "battery"
    property real level: 0
    property bool charging: false
    property bool connected: true
    property color ink: "white"
    implicitWidth: 16; implicitHeight: 18
    onLevelChanged: requestPaint()
    onChargingChanged: requestPaint()
    onConnectedChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        let c = getContext("2d"); c.reset(); c.scale(width / 16, height / 18);
        c.fillStyle = ink; c.strokeStyle = ink; c.lineWidth = 1.4;
        if (kind === "battery") {
            c.strokeRect(3, 3, 10, 14); c.fillRect(6, 0, 4, 2);
            let fill = 11 * Math.max(0, Math.min(1, level)); c.fillRect(5, 15 - fill, 6, fill);
            if (charging) { c.strokeStyle = "#202020"; c.beginPath(); c.moveTo(9, 5); c.lineTo(6, 10); c.lineTo(10, 10); c.lineTo(7, 14); c.stroke(); }
        } else {
            for (let i = 0; i < 4; ++i) { c.globalAlpha = connected && level > i / 4 ? 1 : 0.22; c.fillRect(i * 4, 15 - i * 4, 3, 3 + i * 4); }
            if (!connected) { c.globalAlpha = 1; c.beginPath(); c.moveTo(1, 1); c.lineTo(15, 17); c.stroke(); }
        }
    }
}
