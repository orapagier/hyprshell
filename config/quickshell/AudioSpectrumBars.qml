pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: spectrum
    property var levels: []
    property int barCount: 12
    property bool active: true
    property color color: "#94e2d5"
    property bool variableOpacity: true
    property bool contrastEdge: false
    property color edgeColor: "transparent"
    property real spacing: 2
    property real minimumHeight: 2
    implicitWidth: 58
    implicitHeight: 16
    Row {
        anchors.fill: parent
        spacing: spectrum.spacing
        Repeater {
            model: spectrum.barCount
            delegate: Rectangle {
                required property int index
                objectName: "spectrumBar" + index
                readonly property real level: spectrum.active ? Math.max(0, Math.min(1, Number(spectrum.levels[index]) || 0)) : 0
                property real animatedHeight: spectrum.minimumHeight + level * Math.max(0, spectrum.height - spectrum.minimumHeight)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, (spectrum.width - (spectrum.barCount - 1) * spectrum.spacing) / spectrum.barCount)
                height: spectrum.active ? animatedHeight : spectrum.minimumHeight
                radius: Math.min(width / 2, spectrum.minimumHeight * 0.75)
                antialiasing: true
                color: spectrum.color
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -0.75
                    z: -1
                    radius: parent.radius + 0.75
                    visible: spectrum.contrastEdge
                    color: spectrum.edgeColor
                    antialiasing: true
                }
                opacity: spectrum.variableOpacity ? 0.45 + level * 0.55 : 1
                Behavior on animatedHeight { enabled: spectrum.active; NumberAnimation { duration: 40; easing.type: Easing.OutQuad } }
            }
        }
    }
}
