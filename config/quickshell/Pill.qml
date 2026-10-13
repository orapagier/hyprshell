import QtQuick
import "AdaptiveColors.js" as Colors

Item {
    id: pill
    property var settings: ({})
    property bool vertical: false
    readonly property string shownText: settings.hideText ? "" : settings.text || text
    readonly property string shownIcon: settings.hideIcon ? "" : settings.icon || icon
    readonly property color textColor: settings.textColor || (family === "GoMono Nerd Font" ? settings.iconColor : "") || effectiveForeground
    readonly property color iconColor: settings.iconColor || effectiveForeground
    function styledBackground(base) {
        let c = settings.backgroundColor ? Qt.color(settings.backgroundColor) : base;
        return Qt.rgba(c.r, c.g, c.b, settings.backgroundOpacity >= 0 ? settings.backgroundOpacity : base.a);
    }
    property string text: ""
    property string icon: ""
    property bool blink: false
    property real glyphOpacity: 1
    onBlinkChanged: if (!blink) glyphOpacity = 1
    SequentialAnimation on glyphOpacity {
        running: pill.blink && pill.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: 500 }
        NumberAnimation { to: 1; duration: 500 }
        onRunningChanged: if (!running) pill.glyphOpacity = 1
    }
    property int iconSize: 16
    property color foreground: "#cdd6f4"
    property var colorSampler: null
    property Item colorRoot: null
    property string colorStyle: "normal"
    readonly property var adaptivePalette: colorSampler ? colorSampler.paletteFor(pill, colorRoot, settings.vibrantColor ? Qt.color(settings.vibrantColor) : foreground, settings.vibrantColor ? (bare ? "vibrant-bare" : "vibrant") : (bare ? "bare-" + colorStyle : colorStyle)) : null
    readonly property color effectiveForeground: adaptivePalette ? adaptivePalette.foreground : settings.vibrantColor || foreground
    property color tint: Qt.rgba(30/255, 30/255, 46/255, 0.28)
    property color outline: Qt.rgba(1, 1, 1, 0.16)
    property string family: "DejaVu Sans"
    property int pixelSize: 12
    property bool bold: true
    property int leftPadding: 11
    property int rightPadding: 11
    property int effectiveLeftPadding: Math.max(0, leftPadding + (settings.paddingLeft || 0))
    readonly property int effectiveRightPadding: Math.max(0, rightPadding + (settings.paddingRight || 0))
    property int minimumTextWidth: 0
    property int maximumWidth: 10000
    property int textFormat: Text.PlainText
    property bool interactive: true
    property bool raised: true
    property bool backgroundVisible: true
    readonly property bool backgroundShown: settings.background === "on" || (settings.background !== "off" && backgroundVisible)
    readonly property bool bare: !backgroundShown && !settings.sharedBackgroundShown
    readonly property color glyphShadow: (0.2126 * effectiveForeground.r + 0.7152 * effectiveForeground.g + 0.0722 * effectiveForeground.b) > 0.5 ? Qt.rgba(0.025, 0.03, 0.05, 0.45) : Qt.rgba(1, 1, 1, 0.35)
    readonly property bool glyphHalo: bare && !!adaptivePalette && adaptivePalette.glyphHalo === true
    readonly property color textEdge: Colors.glyphEdge(textColor)
    readonly property color iconEdge: Colors.glyphEdge(iconColor)
    readonly property bool hovered: pointer.containsMouse
    property bool selected: false
    property color hoverTint: tint
    property alias content: label
    signal clicked(var mouse)
    signal wheel(var event)
    signal entered()
    signal exited()
    readonly property bool labelIsIcon: family === "GoMono Nerd Font"
    readonly property int effectiveIconSize: settings.iconSize || settings.fontSize || iconSize
    readonly property int effectiveGlyphSize: settings.iconSize || settings.fontSize || pixelSize
    readonly property int effectiveTextSize: settings.fontSize || Math.max(8, Math.round(pixelSize * (settings.iconSize || 16) / 16))
    readonly property int iconWidth: shownIcon.length ? effectiveIconSize + 5 : 0
    implicitWidth: Math.min(maximumWidth, Math.max(minimumTextWidth, label.implicitWidth, vertical && shownIcon.length ? effectiveIconSize : 0) + (vertical ? 0 : iconWidth) + effectiveLeftPadding + effectiveRightPadding)
    implicitHeight: vertical ? Math.max(28, (shownIcon.length ? effectiveIconSize + (shownText.length ? 4 : 0) : 0) + (shownText.length ? label.implicitHeight : 0) + 8) : Math.max(28, shownIcon.length ? effectiveIconSize + 8 : 0, shownText.length ? label.implicitHeight + 8 : 0)
    Rectangle {
        visible: pill.backgroundShown
        anchors.fill: parent
        radius: pill.settings.radius >= 0 ? pill.settings.radius : height / 2
        color: pill.styledBackground(pill.adaptivePalette
            ? (pill.selected ? pill.adaptivePalette.selected : pointer.containsMouse ? pill.adaptivePalette.hover : pill.adaptivePalette.tint)
            : pill.selected ? Qt.rgba(pill.foreground.r, pill.foreground.g, pill.foreground.b, 0.32) : pointer.containsMouse ? pill.hoverTint : pill.tint)
        Behavior on color { ColorAnimation { duration: 200 } }
        border.width: 1
        border.color: pill.settings.outlineColor || (pill.adaptivePalette ? (pill.selected ? pill.adaptivePalette.selectedOutline : pill.adaptivePalette.outline)
            : pill.selected ? Qt.rgba(pill.foreground.r, pill.foreground.g, pill.foreground.b, 0.65) : pill.outline)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius
            visible: pill.raised
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.08) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            x: 6; y: 1; width: parent.width - 12; height: 1
            visible: pill.raised
            color: Qt.rgba(1, 1, 1, 0.10)
        }
    }
    Rectangle {
        objectName: "bareIndicator"
        visible: pill.bare
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 1
        width: Math.min(14, Math.max(6, parent.width - 8))
        height: 2
        radius: 1
        color: pill.shownIcon.length ? pill.iconColor : pill.textColor
        opacity: pill.selected ? 0.95 : pill.interactive && pill.hovered ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Text {
        x: pill.vertical ? (parent.width - width) / 2 : pill.effectiveLeftPadding
        y: pill.vertical && pill.shownText.length ? 4 : (parent.height - height) / 2
        objectName: "pillIcon"
        opacity: pill.glyphOpacity
        width: pill.effectiveIconSize
        visible: pill.shownIcon.length > 0
        text: pill.shownIcon
        color: pill.iconColor
        style: pill.glyphHalo ? Text.Outline : pill.bare ? Text.Raised : Text.Normal
        styleColor: pill.glyphHalo ? pill.iconEdge : pill.glyphShadow
        font.family: "GoMono Nerd Font"; font.pixelSize: pill.effectiveIconSize
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.QtRendering
    }
    Text {
        id: label
        opacity: pill.glyphOpacity
        x: pill.effectiveLeftPadding + (pill.vertical ? 0 : pill.iconWidth)
        y: (parent.height - height + (pill.vertical && pill.shownIcon.length ? pill.effectiveIconSize + 4 : 0)) / 2
        width: Math.max(1, parent.width - pill.effectiveLeftPadding - pill.effectiveRightPadding - (pill.vertical ? 0 : pill.iconWidth))
        wrapMode: pill.vertical ? Text.Wrap : Text.NoWrap
        text: pill.shownText
        textFormat: pill.textFormat
        color: pill.textColor
        style: pill.glyphHalo ? Text.Outline : pill.bare ? Text.Raised : Text.Normal
        styleColor: pill.glyphHalo ? pill.textEdge : pill.glyphShadow
        font.family: pill.family
        font.pixelSize: pill.labelIsIcon ? pill.effectiveGlyphSize : pill.effectiveTextSize
        font.bold: pill.bold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: pill.vertical ? Text.ElideNone : Text.ElideRight
        renderType: Text.QtRendering
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: pill.interactive ? Qt.LeftButton | Qt.RightButton | Qt.MiddleButton : Qt.NoButton
        cursorShape: pill.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: pill.entered()
        onExited: pill.exited()
        onClicked: mouse => pill.clicked(mouse)
        onWheel: event => pill.wheel(event)
    }
}
