import QtQuick

// A static vector illustration. Repaint only when the displayed conditions change.
Canvas {
    id: glyph
    property int code: 3
    property bool daylight: true
    property color cloudColor: "#dbe3f4"
    property color accentColor: "#b4befe"
    implicitWidth: 112
    implicitHeight: 100
    onCodeChanged: requestPaint()
    onDaylightChanged: requestPaint()
    onCloudColorChanged: requestPaint()
    onAccentColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset(); ctx.scale(width / 112, height / 100);
        const cloudy = code !== 0;
        const wet = [51,53,55,56,57,61,63,65,66,67,80,81,82,95,96,99].includes(code);
        const snowy = [71,73,75,77,85,86].includes(code);
        const sunX = cloudy ? 75 : 56, sunY = cloudy ? 31 : 46;
        if (code <= 2) {
            ctx.fillStyle = daylight ? "#efc78e" : cloudColor;
            ctx.globalAlpha = 0.10;
            ctx.beginPath(); ctx.arc(sunX, sunY, 32, 0, Math.PI * 2); ctx.fill();
            ctx.globalAlpha = 1;
            ctx.beginPath(); ctx.arc(sunX, sunY, daylight ? 17 : 19, 0, Math.PI * 2); ctx.fill();
            if (daylight) {
                ctx.lineWidth = 2; ctx.strokeStyle = "#efc78e"; ctx.lineCap = "round";
                for (let i = 0; i < 8; i++) {
                    const angle = i * Math.PI / 4;
                    ctx.beginPath(); ctx.moveTo(sunX + Math.cos(angle) * 23, sunY + Math.sin(angle) * 23);
                    ctx.lineTo(sunX + Math.cos(angle) * 27, sunY + Math.sin(angle) * 27); ctx.stroke();
                }
            } else {
                ctx.globalCompositeOperation = "destination-out";
                ctx.beginPath(); ctx.arc(sunX + 9, sunY - 7, 17, 0, Math.PI * 2); ctx.fill();
                ctx.globalCompositeOperation = "source-over";
            }
        }
        if (cloudy) {
            const fill = ctx.createLinearGradient(0, 25, 0, 72);
            fill.addColorStop(0, cloudColor); fill.addColorStop(1, accentColor);
            ctx.fillStyle = fill;
            ctx.beginPath(); ctx.moveTo(30, 70);
            ctx.bezierCurveTo(8, 70, 8, 43, 27, 42);
            ctx.bezierCurveTo(29, 17, 65, 16, 73, 39);
            ctx.bezierCurveTo(98, 32, 109, 70, 82, 70);
            ctx.closePath(); ctx.fill();
            ctx.globalAlpha = 0.16; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1; ctx.stroke(); ctx.globalAlpha = 1;
        }
        ctx.strokeStyle = accentColor; ctx.lineWidth = 3; ctx.lineCap = "round";
        if (wet && code < 95) {
            for (let x of [35, 55, 75]) {
                ctx.beginPath(); ctx.moveTo(x, 79); ctx.lineTo(x - 4, 88); ctx.stroke();
            }
        } else if (code >= 95) {
            ctx.fillStyle = "#efc78e";
            ctx.beginPath(); ctx.moveTo(57, 74); ctx.lineTo(46, 88); ctx.lineTo(55, 88);
            ctx.lineTo(50, 99); ctx.lineTo(69, 81); ctx.lineTo(59, 81); ctx.lineTo(64, 74); ctx.closePath(); ctx.fill();
        } else if (snowy) {
            for (let x of [34, 56, 78]) {
                ctx.beginPath(); ctx.moveTo(x, 79); ctx.lineTo(x, 89); ctx.moveTo(x - 4, 81); ctx.lineTo(x + 4, 87);
                ctx.moveTo(x - 4, 87); ctx.lineTo(x + 4, 81); ctx.stroke();
            }
        } else if ([45,48].includes(code)) {
            ctx.globalAlpha = 0.5;
            for (let y of [80, 89]) { ctx.beginPath(); ctx.moveTo(27, y); ctx.lineTo(83, y); ctx.stroke(); }
        }
    }
}
