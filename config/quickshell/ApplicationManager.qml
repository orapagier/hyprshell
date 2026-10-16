pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "ApplicationModel.js" as Apps
import "SettingsModel.js" as Settings

ColumnLayout {
    id: manager
    required property var service
    property string component: 'hyprdock'
    property string selectedAddress: ''
    readonly property var config: service.store.config
    readonly property var pins: Settings.effectivePins(config, component)
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
    ColumnLayout {
        Layout.fillWidth: true
        SettingsComboBox {
            objectName: 'pinComponent'
            Layout.fillWidth: true
            model: ['Hyprdock pins', 'Hyprbar pins']
            onActivated: manager.component = currentIndex === 0 ? 'hyprdock' : 'hyprbar'
        }
        SettingsCheckBox {
            text: 'Shared pins'
            checked: manager.config.pins.mode === 'shared'
            enabled: !manager.service.busy
            onClicked: manager.service.edit({action: 'mode', mode: checked ? 'shared' : 'separate'})
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        SettingsComboBox {
            id: installed
            objectName: 'pinApplication'
            Layout.fillWidth: true
            model: manager.appChoices.map(app => app.name)
            displayText: currentIndex < 0 ? 'Choose an installed app' : currentText
        }
        MenuButton {
            text: 'Pin'
            Layout.fillWidth: true
            enabled: !manager.service.busy && installed.currentIndex >= 0
            onClicked: manager.service.edit({action: 'pin', component: manager.component, id: manager.appChoices[installed.currentIndex].id})
        }
    }
    Text { Layout.fillWidth: true; text: 'Pins · select an app to launch'; color: '#a6adc8'; font.pixelSize: 12; wrapMode: Text.Wrap }
    ListView {
        id: pinList
        objectName: 'applicationPins'
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(100, Math.max(36, contentHeight))
        clip: true; spacing: 4
        model: manager.pins
        delegate: RowLayout {
            required property string modelData
            required property int index
            width: pinList.width
            AppListButton {
                Layout.fillWidth: true
                readonly property var entry: manager.service.entry(modelData)
                text: entry ? entry.name : modelData + ' (not installed)'
                iconSource: manager.service.iconSource(entry ? entry.icon : '')
                enabled: !!entry
                onClicked: manager.service.launch(modelData)
            }
            MenuButton {
                text: '↑'; Accessible.name: 'Move pin earlier'
                enabled: index > 0 && !manager.service.busy
                onClicked: manager.service.edit({action: 'reorder', component: manager.component, id: modelData, index: index - 1})
            }
            MenuButton {
                text: '↓'; Accessible.name: 'Move pin later'
                enabled: index < manager.pins.length - 1 && !manager.service.busy
                onClicked: manager.service.edit({action: 'reorder', component: manager.component, id: modelData, index: index + 1})
            }
            MenuButton {
                text: 'Unpin'; enabled: !manager.service.busy
                onClicked: manager.service.edit({action: 'unpin', component: manager.component, id: modelData})
            }
        }
        Text { visible: !manager.pins.length; text: 'No pinned apps'; color: '#a6adc8'; font.pixelSize: 12 }
        ScrollBar.vertical: ScrollBar {}
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
            text: 'Pin app'; enabled: !!manager.selected && !!manager.selected.appId && !manager.service.busy
            onClicked: manager.service.edit({action: 'pin', component: manager.component, id: manager.selected.appId})
        }
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
