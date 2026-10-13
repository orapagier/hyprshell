import QtQuick

// Window shortcuts also work when a power-menu button owns keyboard focus.
Item {
    id: shortcuts
    property bool active: false
    signal triggered(int key)
    Repeater {
        model: ["L", "X", "R", "S", "O"]
        delegate: Item {
            required property string modelData
            Shortcut {
                sequences: [modelData, "Alt+" + modelData]
                context: Qt.WindowShortcut
                enabled: shortcuts.active
                autoRepeat: false
                onActivated: shortcuts.triggered(modelData.charCodeAt(0))
            }
        }
    }
}
