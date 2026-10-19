pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Four tiny, input-transparent surfaces. No panel or workspace reservation.
Scope {
    id: corners
    property int radius: 20
    Variants {
        model: Quickshell.screens
        Scope {
            id: output
            required property var modelData
            Variants {
                model: [0, 1, 2, 3]
                PanelWindow {
                    id: corner
                    required property int modelData
                    screen: output.modelData
                    implicitWidth: corners.radius
                    implicitHeight: corners.radius
                    anchors.top: modelData < 2
                    anchors.bottom: modelData >= 2
                    anchors.left: modelData % 2 === 0
                    anchors.right: modelData % 2 === 1
                    color: "transparent"
                    exclusiveZone: -1
                    exclusionMode: ExclusionMode.Ignore
                    mask: Region {}
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "hyprshell-corners"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        transform: Scale {
                            origin.x: corner.width / 2
                            origin.y: corner.height / 2
                            xScale: corner.modelData % 2 === 1 ? -1 : 1
                            yScale: corner.modelData >= 2 ? -1 : 1
                        }
                        ShapePath {
                            strokeWidth: -1
                            fillColor: "black"
                            startX: 0; startY: corners.radius
                            PathLine { x: 0; y: 0 }
                            PathLine { x: corners.radius; y: 0 }
                            PathArc { x: 0; y: corners.radius; radiusX: corners.radius; radiusY: corners.radius; direction: PathArc.Counterclockwise }
                        }
                    }
                }
            }
        }
    }
}
