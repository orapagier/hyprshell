import QtQuick

// Layer-shell keyboard focus need not make its window Qt's active window.
// Scope application shortcuts explicitly to the pinned power menu instead.
Item {
    id: shortcuts
    property bool active: false
    signal triggered(int key)
    function handleKey(event) {
        if (!active || event.isAutoRepeat
                || (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier))
                || ![Qt.Key_L, Qt.Key_X, Qt.Key_R, Qt.Key_S, Qt.Key_O].includes(event.key)) return;
        event.accepted = true;
        triggered(event.key);
    }
    Repeater {
        model: ["L", "X", "R", "S", "O"]
        delegate: Item {
            required property string modelData
            Shortcut {
                sequences: [modelData, "Alt+" + modelData]
                context: Qt.ApplicationShortcut
                enabled: shortcuts.active
                autoRepeat: false
                onActivated: shortcuts.triggered(modelData.charCodeAt(0))
            }
        }
    }
}
