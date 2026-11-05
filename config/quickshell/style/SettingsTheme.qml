pragma Singleton
import QtQuick
import "../AdaptiveColors.js" as Colors

// Keep broad surfaces nearly neutral; reserve wallpaper color for accents.
QtObject {
    property color wallpaperSample: "#141721"
    readonly property real textScale: Theme.textScale
    readonly property bool highContrast: Theme.highContrast
    readonly property bool reducedMotion: Theme.reducedMotion
    readonly property color background: highContrast ? "#000000"
        : Qt.hsva(wallpaperSample.hsvHue, Math.min(0.10, wallpaperSample.hsvSaturation * 0.14), 0.105, 1)
    readonly property color sidebar: highContrast ? "#0c0c0c" : Colors.mix(background, Qt.color("#000000"), 0.22)
    readonly property color pane: highContrast ? "#000000" : Colors.mix(background, text, 0.025)
    readonly property color surface: highContrast ? "#161616" : Colors.mix(background, text, 0.045)
    readonly property color card: highContrast ? "#161616" : Colors.mix(background, text, 0.045)
    readonly property color cardHover: highContrast ? "#242424" : Colors.mix(background, text, 0.075)
    readonly property color hero: highContrast ? "#101010" : Colors.mix(background, text, 0.065)
    readonly property color navRow: highContrast ? "#111111" : Colors.mix(background, text, 0.035)
    readonly property color navSelected: highContrast ? "#333333" : Colors.mix(background, accent, 0.20)
    readonly property color iconBadge: highContrast ? "#2c2c2c" : Colors.mix(background, text, 0.085)
    readonly property color iconBadgeActive: highContrast ? "#f0f0f0" : Colors.mix(background, accent, 0.27)
    readonly property color iconBadgeText: highContrast ? "#ffffff" : accent
    readonly property color iconBadgeTextActive: highContrast ? "#000000" : accent
    readonly property color statusPill: highContrast ? "#1a1a1a" : Colors.mix(background, accent, 0.07)
    readonly property color field: highContrast ? "#000000" : Colors.mix(background, text, 0.015)
    readonly property color button: highContrast ? "#222222" : Colors.mix(background, text, 0.09)
    readonly property color hover: highContrast ? "#303030" : Colors.mix(background, text, 0.13)
    readonly property color pressed: highContrast ? "#404040" : Colors.mix(background, text, 0.17)
    readonly property color border: highContrast ? "#ffffff" : Colors.mix(background, text, 0.14)
    readonly property color controlBorder: highContrast ? "#ffffff" : Colors.mix(background, accent, 0.55)
    readonly property color separator: highContrast ? "#8a8a8a" : border
    readonly property color divider: highContrast ? "#7a7a7a" : Colors.mix(background, text, 0.14)
    readonly property color text: highContrast ? "#ffffff" : "#f0f1ef"
    readonly property color muted: highContrast ? "#e8e8e8" : Colors.mix(background, text, 0.72)
    readonly property color disabled: highContrast ? "#a8a8a8" : Colors.mix(background, text, 0.46)
    readonly property color accent: highContrast ? "#ffffff"
        : Qt.hsla(wallpaperSample.hslHue, Math.min(0.38, wallpaperSample.hslSaturation * 0.5), 0.76, 1)
    readonly property color accentHover: Colors.mix(accent, Qt.color("#ffffff"), 0.18)
    readonly property color accentPressed: Colors.mix(accent, background, 0.12)
    readonly property color accentText: accent
    readonly property color selection: highContrast ? "#244d3e" : Colors.mix(background, accent, 0.22)
    readonly property color accentForeground: highContrast ? "#000000" : Colors.mix(background, Qt.color("#000000"), 0.45)
    readonly property color success: "#a5d6c2"
    readonly property color warning: "#eed099"
    readonly property color danger: "#ffadb6"
    readonly property int bodySize: Math.round(14 * textScale)
    readonly property int captionSize: Math.round(12 * textScale)
    readonly property int sectionSize: Math.round(14 * textScale)
    readonly property int titleSize: Math.round(30 * textScale)
    readonly property int pageTitleSize: Math.round(34 * textScale)
    readonly property int pageTitleCompactSize: Math.round(28 * textScale)
    readonly property int navHintSize: Math.round(11 * textScale)
    readonly property int navRowHeight: Math.round(56 * textScale)
    readonly property int iconBadgeSize: Math.round(34 * textScale)
    readonly property int radius: 16
    readonly property int cardRadius: 20
    readonly property int paneRadius: 26
    readonly property int fieldRadius: 13
    readonly property int controlRadius: 10
    readonly property int controlHeight: Math.round(40 * textScale)
    readonly property int pageMaxWidth: 880
    readonly property int hoverDuration: 150
    readonly property int spatialDuration: 220
    readonly property var effectsCurve: [0.2, 0.8, 0.2, 1, 1, 1]
    readonly property var spatialCurve: [0.2, 0.8, 0.2, 1, 1, 1]
    function duration(item, milliseconds) { return Theme.duration(item, milliseconds); }
}
