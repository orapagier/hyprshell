pragma Singleton
import QtQuick

QtObject {
    property var preferences: ({})
    readonly property real textScale: Math.max(1, Math.min(1.5, preferences.textScale || 1))
    readonly property bool highContrast: preferences.highContrast === true
    readonly property bool reducedMotion: preferences.reducedMotion === true
    readonly property color background: highContrast ? "#000000" : "#202020"
    readonly property color sidebar: highContrast ? "#0c0c0c" : "#282828"
    readonly property color surface: highContrast ? "#161616" : "#303030"
    readonly property color field: highContrast ? "#000000" : "#252525"
    readonly property color button: highContrast ? "#222222" : "#414141"
    readonly property color hover: "#494949"
    readonly property color pressed: "#545454"
    readonly property color border: highContrast ? "#ffffff" : "#484848"
    readonly property color controlBorder: highContrast ? "#ffffff" : "#858585"
    readonly property color separator: highContrast ? "#8a8a8a" : "#383838"
    readonly property color text: highContrast ? "#ffffff" : "#f5f5f5"
    readonly property color muted: highContrast ? "#e8e8e8" : "#b8b8b8"
    readonly property color disabled: highContrast ? "#a8a8a8" : "#858585"
    readonly property color accent: "#2874cc"
    readonly property color accentHover: "#2c76ca"
    readonly property color accentPressed: "#2462ad"
    readonly property color accentText: highContrast ? "#b7dcff" : "#8ec1ff"
    readonly property color selection: highContrast ? "#124980" : "#33455b"
    readonly property color accentForeground: "#ffffff"
    readonly property color success: "#8fd4a0"
    readonly property color warning: "#f1ce88"
    readonly property color danger: "#ff9ca5"
    readonly property int bodySize: Math.round(14 * textScale)
    readonly property int captionSize: Math.round(12 * textScale)
    readonly property int sectionSize: Math.round(15 * textScale)
    readonly property int titleSize: Math.round(26 * textScale)
    readonly property int radius: 12
    readonly property int controlRadius: 8
    readonly property int controlHeight: Math.round(38 * textScale)
    function duration(item, milliseconds) {
        if (reducedMotion) return 0;
        for (let parent = item; parent; parent = parent.parent) {
            if (parent.settingsMotionEnabled !== undefined)
                return parent.settingsMotionEnabled ? milliseconds : 0;
        }
        return milliseconds;
    }
}
