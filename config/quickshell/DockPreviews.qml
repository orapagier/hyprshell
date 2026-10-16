pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

ListView {
    id: previews
    required property var service
    property var group: null
    signal closeRequested()
    implicitHeight: 148
    orientation: ListView.Horizontal
    spacing: 8
    clip: true
    model: group ? group.windows : []
    boundsBehavior: Flickable.StopAtBounds
    WheelHandler {
        target: null
        onWheel: event => {
            previews.contentX = Math.max(0, Math.min(Math.max(0, previews.contentWidth - previews.width),
                previews.contentX - (event.angleDelta.y || event.angleDelta.x) / 120 * 228));
            event.accepted = true;
        }
    }
    delegate: Item {
        id: tile
        required property var modelData
        width: Math.min(220, previews.width); height: 140
        MenuButton {
            id: previewButton
            objectName: 'dockPreview-' + tile.modelData.address
            anchors.fill: parent
            padding: 0
            Accessible.name: 'Focus ' + tile.modelData.title
            onClicked: if (previews.service.windowAction('focus', tile.modelData.address)) previews.closeRequested()
            background: Rectangle {
                radius: 8
                color: previewButton.hovered ? '#313244' : '#181825'
                border.color: previewButton.activeFocus ? '#cba6f7' : '#45475a'
            }
            contentItem: Item {
                Loader {
                    id: capture
                    anchors.fill: parent
                    active: previews.visible && !!tile.modelData.handle?.wayland
                        && tile.x + tile.width > previews.contentX && tile.x < previews.contentX + previews.width
                    source: active ? Qt.resolvedUrl('PreviewCapture.qml') : ''
                    onLoaded: {
                        item.source = Qt.binding(() => tile.modelData.handle?.wayland || null);
                        item.active = true;
                    }
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    visible: !capture.item || !capture.item.hasContent
                    text: tile.modelData.title
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: '#a6adc8'; font.pixelSize: 12
                }
            }
        }
        MenuButton {
            objectName: 'dockPreviewClose-' + tile.modelData.address
            anchors { top: parent.top; right: parent.right; margins: 4 }
            width: 28; height: 28; implicitHeight: 28
            padding: 0
            text: '×'
            Accessible.name: 'Close ' + tile.modelData.title
            contentItem: Text {
                text: '×'; color: '#cdd6f4'; font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: 14; color: '#dd181825'; border.color: '#6c7086' }
            onClicked: previews.service.windowAction('close', tile.modelData.address)
        }
    }
    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
}
