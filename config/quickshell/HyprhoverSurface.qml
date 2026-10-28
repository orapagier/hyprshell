pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls.Basic
import "style" as Style

// Top-facing counterpart of the dashboard: a broad edge attachment, with
// concave feet at the screen boundaries and no trigger connector.
Item {
    id: surface
    property bool opened: false
    property string alignment: "center"
    property url wallpaperSource: ""
    property real translucency: 0.06
    property Component page
    property bool instant: false
    readonly property var pageItem: loader.item
    readonly property var menuColors: glass.menuColors
    readonly property real bodyWidth: Math.min(520, Math.max(0, width - 56))
    readonly property real bodyX: alignment === "left" ? 0 : alignment === "right" ? width - bodyWidth : (width - bodyWidth) / 2
    property real bodyHeight: Math.min(Math.max(0, height - 32), 650, Math.max(260, scroll.contentHeight + 48))
    readonly property real foot: Math.min(28, Math.max(0, (width - bodyWidth) / 2), Math.max(0, height - bodyHeight))
    readonly property rect bodyRect: Qt.rect(bodyX, 0, bodyWidth, bodyHeight)
    readonly property bool rendering: opened || progress > 0.001 || sideways > 0.001
    property real progress: opened ? 1 : 0
    property real sideways: opened ? 1 : 0
    Behavior on progress { enabled: !surface.instant && Style.Theme.duration(surface, 1) > 0; SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.001 } }
    Behavior on sideways { enabled: !surface.instant && Style.Theme.duration(surface, 1) > 0; SpringAnimation { spring: 4; damping: 0.30; epsilon: 0.001 } }
    Behavior on bodyHeight { enabled: surface.opened && surface.progress === 1 && !surface.instant; NumberAnimation { duration: Style.Theme.duration(surface, 180); easing.type: Easing.OutCubic } }
    function containsPoint(point) {
        return point.y >= 0 && point.y <= bodyHeight && point.x >= bodyX && point.x <= bodyX + bodyWidth
            || point.y >= 0 && point.y <= foot && point.x >= bodyX - foot && point.x <= bodyX + bodyWidth + foot
            || alignment !== "center" && point.y <= bodyHeight + foot && point.y >= bodyHeight
                && (alignment === "left" ? point.x <= foot : point.x >= width - foot);
    }
    readonly property bool pointerInside: opened && tracking.hovered && containsPoint(tracking.point.position)
    signal hoverChanged(bool inside)
    onPointerInsideChanged: hoverChanged(pointerInside)
    HoverHandler { id: tracking }
    GlassSurface {
        id: glass
        wallpaperSource: surface.rendering ? surface.wallpaperSource : ""
        screenWidth: surface.width; screenHeight: surface.height
        region: surface.bodyRect
        translucency: surface.translucency
        cacheFullWallpaper: true
    }
    // Mirror the left corner for the right. The center has two top feet.
    readonly property string outline: {
        let w = bodyWidth, h = bodyHeight, f = foot, r = Math.min(24, h / 2);
        if (alignment !== "center")
            return `M 0 0 L ${w+f} 0 Q ${w} 0 ${w} ${f} L ${w} ${h-r} Q ${w} ${h} ${w-r} ${h} L ${f} ${h} Q 0 ${h} 0 ${h+f} Z`;
        let x = bodyX;
        return `M ${x-f} 0 Q ${x} 0 ${x} ${f} L ${x} ${h-r} Q ${x} ${h} ${x+r} ${h} L ${x+w-r} ${h} Q ${x+w} ${h} ${x+w} ${h-r} L ${x+w} ${f} Q ${x+w} 0 ${x+w+f} 0 Z`;
    }
    Item {
        anchors.fill: parent
        visible: surface.rendering
        opacity: Math.min(1, surface.progress * 3)
        transform: Scale {
            origin.x: surface.alignment === "left" ? 0 : surface.alignment === "right" ? surface.width : surface.width / 2
            origin.y: 0
            xScale: surface.alignment === "center" ? 1 + 0.035 * Math.sin(Math.PI * surface.progress) : Math.max(0, surface.sideways)
            yScale: Math.max(0, surface.progress)
        }
        Shape {
            objectName: "hyprhoverAttachedSurface"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: surface.width / 2; xScale: surface.alignment === "right" ? -1 : 1 }
            ShapePath {
                strokeWidth: 1
                strokeColor: glass.rimColor
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: surface.bodyHeight
                    GradientStop { position: 0; color: glass.topColor }
                    GradientStop { position: 0.38; color: glass.middleColor }
                    GradientStop { position: 1; color: glass.bottomColor }
                }
                PathSvg { path: surface.outline }
            }
        }
        MouseArea { x: surface.bodyX; width: surface.bodyWidth; height: surface.bodyHeight }
        Flickable {
            id: scroll
            x: surface.bodyX + 24; y: 24
            width: Math.max(0, surface.bodyWidth - 48)
            height: Math.max(0, surface.bodyHeight - 48)
            contentWidth: width
            contentHeight: loader.item ? loader.item.implicitHeight : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar {}
            Loader {
                id: loader
                width: scroll.width
                active: surface.rendering
                sourceComponent: surface.page
            }
        }
    }
}
