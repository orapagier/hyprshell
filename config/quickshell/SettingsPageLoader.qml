import QtQuick

Loader {
    id: loader
    readonly property bool busy: item !== null && item.busy === true
    readonly property bool dirty: item !== null && item.dirty === true
    active: false
    onVisibleChanged: { if (visible) active = true; else release.restart(); }
    Component.onCompleted: if (visible) active = true
    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onBusyChanged() { if (!loader.visible) release.restart(); }
        function onDirtyChanged() { if (!loader.visible) release.restart(); }
    }
    Timer {
        id: release
        interval: 0
        onTriggered: if (!loader.visible && !loader.busy && !loader.dirty) loader.active = false
    }
}
