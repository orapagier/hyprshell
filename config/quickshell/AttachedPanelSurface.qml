import QtQuick
import QtQuick.Shapes

// A single surface meeting the physical edge; no surrounding screen frame.
Shape {
    id: surface
    property string edge: "top"
    property real start: 12
    property real end: 100
    property color surfaceColor: "#242437"
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
        strokeWidth: -1
        fillColor: surface.surfaceColor
        PathSvg {
            path: {
                let a = surface.first, b = surface.last, r = surface.radius, d = surface.depth;
                return `M ${a-r} 0 Q ${a} 0 ${a} ${r} L ${a} ${d-r} Q ${a} ${d} ${a+r} ${d} L ${b-r} ${d} Q ${b} ${d} ${b} ${d-r} L ${b} ${r} Q ${b} 0 ${b+r} 0 Z`;
            }
        }
    }
}
