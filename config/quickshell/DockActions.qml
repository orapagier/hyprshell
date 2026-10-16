pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: actions
    required property var service
    property var group: null
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
        text: actions.group && actions.group.pinned ? 'Unpin from Hyprdock' : 'Pin to Hyprdock'
        enabled: !!actions.group && !!actions.group.id && !actions.service.busy
        onClicked: actions.service.edit({action:actions.group.pinned ? 'unpin' : 'pin', component:'hyprdock', id:actions.group.id})
    }
    ListView {
        id: windows
        objectName: 'dockWindowPicker'
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(240, contentHeight)
        model: actions.group ? actions.group.windows : []
        clip: true; spacing: 6
        delegate: ColumnLayout {
            required property var modelData
            width: windows.width; spacing: 2
            MenuButton {
                Layout.fillWidth: true
                text: (modelData.active ? '● ' : '') + modelData.title
                Accessible.name: 'Focus ' + modelData.title
                onClicked: if (actions.service.windowAction('focus', modelData.address)) actions.closeRequested()
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
