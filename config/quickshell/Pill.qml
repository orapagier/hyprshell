import QtQuick
import "style" as Style
import "AdaptiveColors.js" as Colors

Item {
    id: pill
    property var settings: ({})
    property bool vertical: false
    readonly property bool uniformItems: settings.uniformItems === true
    property bool iconOnly: vertical
    property bool circular: settings.circularIcons === true
        && (iconOnly || (shownIcon.length > 0 && shownText.length === 0)
            || (labelIsIcon && shownText.length > 0 && !settings.text))
    property real iconOnlyHeight: 0
    property string compactIcon: ""
    readonly property string displayText: shownText
    readonly property string shownText: iconOnly || settings.hideText ? "" : settings.text || text
    readonly property string shownIcon: settings.hideIcon ? "" : settings.icon || (iconOnly ? compactIcon || icon : icon)
    readonly property color textColor: settings.textColor || (family === "GoMono Nerd Font" ? settings.iconColor : "") || effectiveForeground
    readonly property color iconColor: settings.iconColor || effectiveForeground
    function styledBackground(base) {
        let c = settings.backgroundColor ? Qt.color(settings.backgroundColor) : base;
        return Qt.rgba(c.r, c.g, c.b, settings.pillTransparency >= 0 ? 1 : settings.backgroundOpacity >= 0 ? settings.backgroundOpacity : base.a);
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
    readonly property var adaptivePalette: colorSampler ? colorSampler.paletteFor(pill, colorRoot, settings.vibrantColor ? Qt.color(settings.vibrantColor) : foreground, settings.lightForeground ? (bare ? "light-bare" : settings.vibrantColor ? "light" : "light-" + colorStyle) : settings.vibrantColor ? (bare ? "vibrant-bare" : "vibrant") : (bare ? "bare-" + colorStyle : colorStyle), settings.panelAdaptive ? {
        shown:backgroundShown, style:colorStyle, transparency:settings.pillTransparency ?? -1,
        glassSurface:settings.glassSurface === true,
        backgroundOpacity:settings.backgroundOpacity ?? -1, backgroundColor:settings.backgroundColor || "",
        layers:(settings.backingPills || []).map(surface => ({color:surface.backgroundFill, opacity:surface.backgroundAlpha}))
    } : null) : null
    readonly property color effectiveForeground: adaptivePalette ? adaptivePalette.foreground : settings.vibrantColor || foreground
    property color tint: Qt.rgba(30/255, 30/255, 46/255, 0.28)
    property color outline: Qt.rgba(1, 1, 1, 0.16)
    property string family: "DejaVu Sans"
    property int pixelSize: 12
    property bool bold: true
    property int leftPadding: 11
    property int rightPadding: 11
    property int effectiveLeftPadding: uniformItems ? (settings.compactPadding ? 0 : 4) : Math.max(0, (vertical ? Math.min(4, leftPadding) : settings.compactPadding ? 0 : leftPadding) + (settings.paddingLeft || 0))
    property int effectiveRightPadding: uniformItems ? (settings.compactPadding ? 0 : 4) : Math.max(0, (vertical ? Math.min(4, rightPadding) : settings.compactPadding ? 0 : rightPadding) + (settings.paddingRight || 0))
    property int minimumTextWidth: 0
    property int maximumWidth: 10000
    property int textFormat: Text.PlainText
    property bool interactive: true
    property bool raised: true
    // Retain material calculations when a caller supplies a different silhouette.
    property bool drawBackground: true
    property bool backgroundVisible: true
    readonly property bool backgroundShown: settings.background === "on" || (settings.background !== "off" && backgroundVisible)
    readonly property bool bare: !backgroundShown && !settings.sharedBackgroundShown
    readonly property color glyphShadow: (0.2126 * effectiveForeground.r + 0.7152 * effectiveForeground.g + 0.0722 * effectiveForeground.b) > 0.5 ? Qt.rgba(0.025, 0.03, 0.05, 0.45) : Qt.rgba(1, 1, 1, 0.35)
    readonly property bool glyphHalo: !settings.outlineFree && bare && !!adaptivePalette && adaptivePalette.glyphHalo === true
    readonly property color textEdge: Colors.glyphEdge(textColor)
    readonly property color iconEdge: Colors.glyphEdge(iconColor)
    readonly property bool hovered: pointer.containsMouse
    property bool selected: false
    property color hoverTint: Qt.rgba(tint.r, tint.g, tint.b, Math.min(1, tint.a + 0.12))
    readonly property real backgroundAlpha: backgroundShown ? opacity * (settings.pillTransparency >= 0 ? 1 - settings.pillTransparency / 100 : 1) : 0
    readonly property color backgroundFill: styledBackground(adaptivePalette
        ? (selected ? adaptivePalette.selected : hovered || activeFocus ? adaptivePalette.hover : adaptivePalette.tint)
        : selected ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.32) : hovered || activeFocus ? hoverTint : tint)
    property alias content: label
    // Ink bounds exclude the pill padding and font line box. Bare popdowns
    // attach to the visible icon (or text when there is no separate icon).
    readonly property rect textGlyphRect: Qt.rect(
        label.x + (label.horizontalAlignment === Text.AlignLeft ? 0 : label.horizontalAlignment === Text.AlignRight ? label.width - label.implicitWidth : (label.width - label.implicitWidth) / 2) + labelMetrics.tightBoundingRect.x,
        label.y + label.baselineOffset + labelMetrics.tightBoundingRect.y,
        labelMetrics.tightBoundingRect.width, labelMetrics.tightBoundingRect.height)
    readonly property rect iconGlyphRect: Qt.rect(
        iconLabel.x + (vertical || uniformItems ? 0 : (iconLabel.width - iconLabel.implicitWidth) / 2) + compactGlyphMetrics.tightBoundingRect.x,
        iconLabel.y + iconLabel.baselineOffset + compactGlyphMetrics.tightBoundingRect.y,
        compactGlyphMetrics.tightBoundingRect.width, compactGlyphMetrics.tightBoundingRect.height)
    property rect glyphRect: shownIcon.length ? iconGlyphRect : textGlyphRect
    signal clicked(var mouse)
    signal wheel(var event)
    signal entered()
    signal exited()
    readonly property bool labelIsIcon: family === "GoMono Nerd Font"
    readonly property int effectiveIconSize: settings.iconSize || settings.fontSize || iconSize
    readonly property int effectiveGlyphSize: settings.iconSize || settings.fontSize || pixelSize
    readonly property int effectiveTextSize: settings.fontSize || Math.max(8, Math.round(pixelSize * (settings.iconSize || 16) / 16))
    readonly property real iconWidth: shownIcon.length ? (uniformItems && !vertical ? compactGlyphMetrics.tightBoundingRect.width + (shownText.length ? 4 : 0) : effectiveIconSize + 5) : 0
    readonly property real uniformContentWidth: (shownText.length ? (labelIsIcon ? labelMetrics.tightBoundingRect.width : label.implicitWidth) : shownIcon.length ? 0 : minimumTextWidth) + iconWidth
    readonly property real naturalWidth: uniformItems && !vertical
        ? Math.min(maximumWidth, Math.max(circular && (labelIsIcon || shownIcon.length) ? Math.max(24, effectiveIconSize + 8) : 0, uniformContentWidth + effectiveLeftPadding + effectiveRightPadding))
        : Math.min(maximumWidth, Math.max(minimumTextWidth, label.implicitWidth, vertical && shownIcon.length ? effectiveIconSize : 0) + (vertical ? 0 : iconWidth) + effectiveLeftPadding + effectiveRightPadding)
    implicitWidth: naturalWidth
    readonly property real naturalHeight: uniformItems && !vertical ? Math.max(24, effectiveIconSize + 8) : iconOnly ? (iconOnlyHeight > 0 ? iconOnlyHeight : width) : Math.max(28, shownIcon.length ? effectiveIconSize + 8 : 0, shownText.length ? label.implicitHeight + 8 : 0)
    implicitHeight: naturalHeight
    activeFocusOnTab: interactive
    Keys.onReturnPressed: if (interactive) clicked(null)
    Keys.onSpacePressed: if (interactive) clicked(null)
    Rectangle {
        objectName: "pillBackground"
        visible: pill.backgroundShown && pill.drawBackground
        opacity: pill.settings.pillTransparency >= 0 ? 1 - pill.settings.pillTransparency / 100 : 1
        anchors.centerIn: parent
        width: pill.circular ? Math.min(pill.width, pill.height) : pill.width
        height: pill.circular ? width : pill.height
        radius: pill.circular ? width / 2 : pill.vertical ? Math.min(width, height) / 2 : pill.settings.radius >= 0 ? pill.settings.radius : height / 2
        color: pill.backgroundFill
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(pill, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
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
            x: pill.vertical ? parent.width * 0.35 : 6; y: 1
            width: pill.vertical ? parent.width * 0.3 : parent.width - 12; height: 1
            visible: pill.raised
            color: Qt.rgba(1, 1, 1, 0.10)
        }
    }
    TextMetrics {
        id: compactGlyphMetrics
        font: iconLabel.font
        text: iconLabel.text
    }
    TextMetrics {
        id: labelMetrics
        font: label.font
        text: label.text
    }
    Text {
        id: iconLabel
        x: pill.vertical ? (parent.width - compactGlyphMetrics.tightBoundingRect.width) / 2 - compactGlyphMetrics.tightBoundingRect.x : pill.uniformItems && pill.circular ? (parent.width - compactGlyphMetrics.tightBoundingRect.width) / 2 - compactGlyphMetrics.tightBoundingRect.x : pill.effectiveLeftPadding - (pill.uniformItems ? compactGlyphMetrics.tightBoundingRect.x : 0)
        y: pill.vertical && !pill.shownText.length
            ? (parent.height - compactGlyphMetrics.tightBoundingRect.height) / 2 - baselineOffset - compactGlyphMetrics.tightBoundingRect.y
            : pill.vertical ? 4 : (parent.height - height) / 2
        objectName: "pillIcon"
        opacity: pill.glyphOpacity
        width: pill.effectiveIconSize
        visible: pill.shownIcon.length > 0
        text: pill.shownIcon
        color: pill.iconColor
        style: pill.settings.outlineFree ? Text.Normal : pill.glyphHalo ? Text.Outline : pill.bare ? Text.Raised : Text.Normal
        styleColor: pill.glyphHalo ? pill.iconEdge : pill.glyphShadow
        font.family: "GoMono Nerd Font"; font.pixelSize: pill.effectiveIconSize
        horizontalAlignment: pill.vertical || pill.uniformItems ? Text.AlignLeft : Text.AlignHCenter
        renderType: Text.QtRendering
    }
    Text {
        id: label
        opacity: pill.glyphOpacity
        x: pill.uniformItems && !pill.vertical && pill.circular && pill.labelIsIcon
            ? (parent.width - labelMetrics.tightBoundingRect.width) / 2 - labelMetrics.tightBoundingRect.x
            : pill.effectiveLeftPadding + (pill.vertical ? 0 : pill.iconWidth) - (pill.uniformItems && !pill.vertical && pill.labelIsIcon ? labelMetrics.tightBoundingRect.x : 0)
        y: (parent.height - height + (pill.vertical && pill.shownIcon.length ? pill.effectiveIconSize + 4 : 0)) / 2
        width: Math.max(1, parent.width - pill.effectiveLeftPadding - pill.effectiveRightPadding - (pill.vertical ? 0 : pill.iconWidth))
        wrapMode: Text.NoWrap
        text: pill.displayText
        textFormat: pill.textFormat
        color: pill.textColor
        style: pill.settings.outlineFree ? Text.Normal : pill.glyphHalo ? Text.Outline : pill.bare ? Text.Raised : Text.Normal
        styleColor: pill.glyphHalo ? pill.textEdge : pill.glyphShadow
        font.family: pill.family
        font.pixelSize: pill.labelIsIcon ? pill.effectiveGlyphSize : pill.effectiveTextSize
        font.bold: pill.bold
        horizontalAlignment: pill.uniformItems && !pill.vertical && (!pill.circular || pill.labelIsIcon) ? Text.AlignLeft : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: pill.vertical || (pill.uniformItems && pill.labelIsIcon) ? Text.ElideNone : Text.ElideRight
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
        onWheel: event => { event.accepted = false; pill.wheel(event); }
    }
}
