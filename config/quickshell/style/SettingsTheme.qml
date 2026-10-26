pragma Singleton
import QtQuick

// Settings owns its palette; desktop surfaces keep their wallpaper colors.
QtObject {
    readonly property real textScale: Theme.textScale
    readonly property bool highContrast: Theme.highContrast
    readonly property bool reducedMotion: Theme.reducedMotion
    readonly property color background: highContrast ? "#000000" : "#191b20"
    readonly property color sidebar: highContrast ? "#0c0c0c" : "#131519"
    readonly property color surface: highContrast ? "#161616" : "#22252b"
    readonly property color field: highContrast ? "#000000" : "#191c21"
    readonly property color button: highContrast ? "#222222" : "#30343c"
    readonly property color hover: highContrast ? "#303030" : "#2c3139"
    readonly property color pressed: highContrast ? "#404040" : "#363e46"
    readonly property color border: highContrast ? "#ffffff" : "#343942"
    readonly property color controlBorder: highContrast ? "#ffffff" : "#666f7c"
    readonly property color separator: highContrast ? "#8a8a8a" : "#30343c"
    readonly property color text: highContrast ? "#ffffff" : "#eceef2"
    readonly property color muted: highContrast ? "#e8e8e8" : "#a3aab6"
    readonly property color disabled: highContrast ? "#a8a8a8" : "#7f8793"
    readonly property color accent: "#a5d6c2"
    readonly property color accentHover: "#bce5d4"
    readonly property color accentPressed: "#8ac3ac"
    readonly property color accentText: highContrast ? "#c6ffe6" : "#b1dfcc"
    readonly property color selection: highContrast ? "#244d3e" : "#263b34"
    readonly property color accentForeground: "#152c22"
    readonly property color success: "#a5d6c2"
    readonly property color warning: "#eed099"
    readonly property color danger: "#ffadb6"
    readonly property int bodySize: Math.round(14 * textScale)
    readonly property int captionSize: Math.round(12 * textScale)
    readonly property int sectionSize: Math.round(14 * textScale)
    readonly property int titleSize: Math.round(30 * textScale)
    readonly property int radius: 16
    readonly property int controlRadius: 10
    readonly property int controlHeight: Math.round(40 * textScale)
    readonly property int hoverDuration: 150
    readonly property int spatialDuration: 220
    readonly property var effectsCurve: [0.2, 0.8, 0.2, 1, 1, 1]
    readonly property var spatialCurve: [0.2, 0.8, 0.2, 1, 1, 1]
    function duration(item, milliseconds) { return Theme.duration(item, milliseconds); }
}
