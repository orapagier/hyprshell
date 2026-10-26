pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style
import "SettingsModel.js" as Model
import "PanelLayout.js" as LayoutModel

SettingsCard {
    id: root
    required property var config
    property int currentWorkspace: 1
    property int selectedPreset: -1
    property string monitor: ''
    property int workspace: currentWorkspace
    readonly property var candidate: selectedPreset < 0 ? config : LayoutModel.preset(config, selectedPreset)
    readonly property var panels: LayoutModel.rows(candidate, monitor, workspace)
    signal layoutChosen(var config)
    title: "Panel layout preview & presets"
    subtitle: "Preview your draft or choose a preset before applying it. Presets change the Hyprpane edge; styling, items, monitor and workspace choices are retained."
    SettingsComboBox {
        objectName: 'panelLayoutPreset'
        Layout.fillWidth: true
        model: ['Current layout', 'Hyprpane · Top', 'Hyprpane · Bottom', 'Hyprpane · Left', 'Hyprpane · Right']
        currentIndex: root.selectedPreset + 1
        Accessible.name: 'Panel layout preset'
        onActivated: root.selectedPreset = currentIndex - 1
    }
    Label { text: 'Preview monitor name'; color: Style.SettingsTheme.text }
    SettingsTextField {
        objectName: 'panelPreviewMonitor'
        Layout.fillWidth: true
        placeholderText: 'eDP-1, HDMI-A-1 (empty previews unlisted monitors)'
        Accessible.name: 'Preview monitor name'
        onTextEdited: root.monitor = text.trim()
    }
    RowLayout {
        Label { text: 'Preview workspace'; color: Style.SettingsTheme.text }
        SpinBox {
            objectName: 'panelPreviewWorkspace'
            from: 1; to: 99; value: root.workspace
            Accessible.name: 'Preview workspace'
            onValueModified: root.workspace = value
        }
    }
    Rectangle {
        id: screen
        objectName: 'panelLayoutDiagram'
        Layout.fillWidth: true
        implicitHeight: 180
        color: Style.SettingsTheme.surface
        border.color: Style.SettingsTheme.border
        radius: 8
        Label {
            anchors.centerIn: parent
            text: 'Workspace ' + root.workspace + (root.monitor ? ' · ' + root.monitor : '\nUnlisted monitor')
            color: Style.SettingsTheme.muted
            horizontalAlignment: Text.AlignHCenter
        }
        Repeater {
            model: root.panels
            delegate: Rectangle {
                id: rail
                required property var modelData
                required property int index
                readonly property bool vertical: modelData.edge === 'left' || modelData.edge === 'right'
                readonly property bool topOccupied: root.panels.some(p => p.shown && p.edge === 'top')
                readonly property bool bottomOccupied: root.panels.some(p => p.shown && p.edge === 'bottom')
                objectName: 'panelPreview_' + modelData.name
                visible: modelData.shown
                color: [Style.SettingsTheme.accentText, Style.SettingsTheme.text, Style.SettingsTheme.muted][index]
                opacity: modelData.hideMode === 'always' ? 1 : 0.5
                radius: 5
                x: modelData.edge === 'right' ? screen.width - 22 : 8
                y: modelData.edge === 'bottom' ? screen.height - 22 : vertical && topOccupied ? 30 : 8
                width: vertical ? 14 : screen.width - 16
                height: vertical ? screen.height - 16 - (topOccupied ? 22 : 0) - (bottomOccupied ? 22 : 0) : 14
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: root.panels.map(p => p.name.replace('hypr', 'Hypr') + ': ' + (!p.enabled ? 'disabled' :
            !p.shown ? 'hidden here' : p.edge + (p.hideMode === 'always' ? '' : ' · ' + p.hideMode))).join('\n')
        color: Style.SettingsTheme.text
        wrapMode: Text.WordWrap
    }
    Label {
        Layout.fillWidth: true
        text: 'Schematic placement preview. Actual dimensions follow Hyprpane settings.'
        color: Style.SettingsTheme.muted
        wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: 'applyPanelLayoutPreset'
        text: 'Apply layout preset'
        enabled: root.selectedPreset >= 0
        onClicked: {
            root.layoutChosen(root.candidate);
            root.selectedPreset = -1;
        }
    }
}
