pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "ApplicationModel.js" as Apps

ColumnLayout {
    id: manager
    required property var service
    property string selectedAddress: ''
    readonly property var config: service.store.config
    readonly property var rows: service.windowRows
    readonly property var selected: rows.find(w => w.address === selectedAddress) || null
    readonly property var appChoices: service.entries.map(e => ({id: Apps.desktopId(e), name: e.name + ' — ' + Apps.desktopId(e)}))
    spacing: 6
    MenuButton {
        objectName:'restoreDesktopWindows'
        Layout.fillWidth:true
        visible:!!manager.service.desktop?.hidden
        text:'Restore desktop windows'
        enabled:!manager.service.desktop?.busy
        onClicked:manager.service.desktop.run('restore')
    }
    Text {
        Layout.fillWidth:true; wrapMode:Text.Wrap; color:'#f38ba8'
        visible:!!manager.service.desktop?.error
        text:manager.service.desktop?.error || ''
    }
    SettingsComboBox {
        id: installed
        objectName: 'matchingApplication'
        Layout.fillWidth: true
        model: manager.appChoices.map(app => app.name)
        displayText: currentIndex < 0 ? 'Choose an installed app for matching' : currentText
    }
    Text { Layout.fillWidth: true; text: 'Running windows · select a window for actions'; color: '#a6adc8'; font.pixelSize: 12; wrapMode: Text.Wrap }
    ListView {
        id: windowList
        objectName: 'applicationWindows'
        Layout.fillWidth: true; Layout.preferredHeight: 110
        model: manager.rows
        clip: true; spacing: 4
        delegate: MenuButton {
            required property var modelData
            width: windowList.width
            text: (modelData.active ? '● ' : '') + modelData.title + ' · ' + modelData.workspaceName + ' · ' + modelData.output
            accent: manager.selectedAddress === modelData.address ? '#cba6f7' : '#cdd6f4'
            onClicked: manager.selectedAddress = modelData.address
        }
        Text { visible: !manager.rows.length; text: 'No running windows'; color: '#a6adc8'; font.pixelSize: 12 }
        ScrollBar.vertical: ScrollBar {}
    }
    RowLayout {
        visible: !!manager.selected
        MenuButton { text: 'Focus'; onClicked: if (manager.selected) manager.service.windowAction('focus', manager.selected.address) }
        MenuButton { text: 'Close'; onClicked: if (manager.selected) manager.service.windowAction('close', manager.selected.address) }
    }
    RowLayout {
        visible: !!manager.selected
        SettingsSpinBox { id: workspace; from: 1; to: 99; value: 1; editable: true; Layout.fillWidth: true; Accessible.name: 'Destination workspace' }
        MenuButton { text: 'Move'; onClicked: if (manager.selected) manager.service.windowAction('move', manager.selected.address, workspace.value) }
    }
    RowLayout {
        visible: !!manager.selected
        MenuButton {
            text: 'New instance'; enabled: !!manager.selected && !!manager.service.entry(manager.selected.appId)
            onClicked: manager.service.launch(manager.selected.appId)
        }
    }
    Text {
        visible: !!manager.selected
        Layout.fillWidth: true
        text: manager.selected ? 'App identity: ' + (manager.selected.identity || 'unavailable') + '\nMatched app: ' + (manager.selected.appId || 'unmatched') : ''
        color: '#a6adc8'; font.pixelSize: 12; wrapMode: Text.Wrap
    }
    ColumnLayout {
        visible: !!manager.selected && !!manager.selected.identity
        Layout.fillWidth: true
        MenuButton {
            text: 'Match to chosen app'
            Layout.fillWidth: true
            enabled: !manager.service.busy && installed.currentIndex >= 0
            onClicked: manager.service.edit({action: 'match', key: manager.selected.identity, id: manager.appChoices[installed.currentIndex].id})
        }
        MenuButton {
            text: 'Automatic match'; enabled: !manager.service.busy
            Layout.fillWidth: true
            onClicked: manager.service.edit({action: 'match', key: manager.selected.identity, id: null})
        }
    }
    Text {
        visible: !!manager.service.error
        text: manager.service.error; color: '#f38ba8'; font.pixelSize: 12
        Layout.fillWidth: true; wrapMode: Text.Wrap
    }
}
