pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: actions
    required property var service
    property var group: null
    property string component: 'hyprdock'
    signal closeRequested()
    signal manageRequested()
    spacing: 6
    MenuButton {
        Layout.fillWidth: true
        text: 'New instance'
        enabled: !!actions.group && actions.group.installed
        onClicked: if (actions.service.launch(actions.group.id)) actions.closeRequested()
    }
    MenuButton {
        Layout.fillWidth: true
        text: (actions.group && actions.group.pinned ? 'Unpin from ' : 'Pin to ') + (actions.component === 'hyprbar' ? 'Hyprbar' : 'Hyprdock')
        enabled: !!actions.group && !!actions.group.id && !actions.service.busy
        onClicked: actions.service.edit({action:actions.group.pinned ? 'unpin' : 'pin', component:actions.component, id:actions.group.id})
    }
    ListView {
        id: windows
        objectName: 'dockWindowPicker'
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(400, contentHeight)
        model: actions.group ? actions.group.windows : []
        clip: true; spacing: 6
        delegate: ColumnLayout {
            id: windowRow
            required property var modelData
            width: windows.width; spacing: 2
            MenuButton {
                id: windowCard
                objectName: 'dockWindowPreview-' + windowRow.modelData.address
                Layout.fillWidth: true
                text: (windowRow.modelData.active ? '● ' : '') + windowRow.modelData.title
                Accessible.name: 'Focus ' + windowRow.modelData.title
                onClicked: if (actions.service.windowAction('focus', windowRow.modelData.address, 0, true)) actions.closeRequested()
                contentItem: ColumnLayout {
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: 6; color: '#181825'; clip: true
                        Loader {
                            id: thumbnail
                            anchors.fill: parent
                            active: actions.visible && !!windowRow.modelData.handle?.wayland
                                && windowRow.y + windowRow.height > windows.contentY
                                && windowRow.y < windows.contentY + windows.height
                            source: active ? Qt.resolvedUrl('PreviewCapture.qml') : ''
                            onLoaded: {
                                item.source = Qt.binding(() => windowRow.modelData.handle?.wayland || null);
                                item.active = true;
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            visible: !thumbnail.item || !thumbnail.item.hasContent
                            text: windowRow.modelData.title + '\nPreview unavailable'
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: '#a6adc8'; font.pixelSize: 12
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: windowCard.text
                        color: '#cdd6f4'; font: windowCard.font
                        elide: Text.ElideRight
                    }
                }
            }
            RowLayout {
                visible: actions.component === 'hyprbar'
                SpinBox { id: destination; from:1; to:99; value:Math.max(1, windowRow.modelData.workspace || 1); Accessible.name:'Destination workspace' }
                MenuButton {
                    objectName:'taskMoveButton'
                    text:'Move'
                    Accessible.name:'Move ' + windowRow.modelData.title + ' to workspace ' + destination.value
                    onClicked: if (actions.service.windowAction('move',windowRow.modelData.address,destination.value)) actions.closeRequested()
                }
            }
            RowLayout {
                Text { Layout.fillWidth: true; text: 'Workspace ' + modelData.workspaceName + ' · ' + modelData.output; color:'#a6adc8'; font.pixelSize:11; elide:Text.ElideRight }
                MenuButton {
                    text: 'Close'; Accessible.name: 'Close ' + modelData.title
                    onClicked: actions.service.windowAction('close', modelData.address)
                }
            }
        }
        ScrollBar.vertical: ScrollBar {}
    }
    MenuButton { Layout.fillWidth:true; text:'App matching and pins…'; onClicked: actions.manageRequested() }
    Text { Layout.fillWidth:true; visible:!!actions.service.error; text:actions.service.error; color:'#f38ba8'; font.pixelSize:12; wrapMode:Text.Wrap }
}
