import QtQuick
import QtQuick.Shapes
import "style" as Style

// A single surface meeting the physical edge; no surrounding screen frame.
Shape {
    id: surface
    property string edge: "top"
    property real start: 12
    property real end: 100
    property color surfaceColor: "#242437"
    property color outlineColor: "transparent"
    property bool raised: false
    Behavior on surfaceColor { ColorAnimation { duration: Style.Theme.duration(surface, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
    readonly property string silhouette: {
        let a = first, b = last, r = radius, d = depth;
        return `M ${a-r} 0 Q ${a} 0 ${a} ${r} L ${a} ${d-r} Q ${a} ${d} ${a+r} ${d} L ${b-r} ${d} Q ${b} ${d} ${b} ${d-r} L ${b} ${r} Q ${b} 0 ${b+r} 0 Z`;
    }
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real length: vertical ? height : width
    readonly property real depth: vertical ? width : height
    readonly property real radius: Math.min(12, depth / 2, Math.max(0, end - start) / 4)
    readonly property real first: Math.max(radius, Math.min(length - radius, start))
    readonly property real last: Math.max(first, Math.min(length - radius, end))
    preferredRendererType: Shape.CurveRenderer
    transform: Matrix4x4 {
        matrix: surface.edge === "left" ? Qt.matrix4x4(0,1,0,0, 1,0,0,0, 0,0,1,0, 0,0,0,1)
            : surface.edge === "right" ? Qt.matrix4x4(0,-1,0,surface.width, 1,0,0,0, 0,0,1,0, 0,0,0,1)
            : surface.edge === "bottom" ? Qt.matrix4x4(1,0,0,0, 0,-1,0,surface.height, 0,0,1,0, 0,0,0,1)
            : Qt.matrix4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
    }
    ShapePath {
        strokeColor: surface.outlineColor
        strokeWidth: surface.outlineColor.a > 0 ? 1 : -1
        fillColor: surface.surfaceColor
        PathSvg { path: surface.silhouette }
    }
    // Match Pill's raised glass wash, clipped to the attached silhouette.
    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: surface.depth
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, surface.raised ? 0.08 : 0) }
            GradientStop { position: 1; color: "transparent" }
        }
        PathSvg { path: surface.silhouette }
    }
    ShapePath {
        strokeWidth: surface.raised ? 1 : -1
        strokeColor: Qt.rgba(1, 1, 1, 0.10)
        fillColor: "transparent"
        // Keep the specular line inside the material, as on individual pills.
        startX: surface.first + surface.radius; startY: 1
        PathLine { x: surface.last - surface.radius; y: 1 }
    }
}
