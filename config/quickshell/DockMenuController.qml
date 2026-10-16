import QtQuick

MenuController {
    id: controller
    readonly property var target: section ? JSON.parse(section) : null
    readonly property string mode: target ? target[0] : ''
    readonly property string groupKey: target ? target[1] : ''
    readonly property rect triggerRect: target ? Qt.rect(target[2], target[3], target[4], target[5]) : Qt.rect(0, 0, 0, 0)

    function token(kind, key, rect) { return JSON.stringify([kind, kind === 'launcher' ? '' : key, rect.x, rect.y, rect.width, rect.height]); }
    function hoverItem(kind, key, rect) { hover(token(kind, key, rect)); }
    function leaveItem(kind, key, rect) { leave(token(kind, key, rect)); }
    function activateItem(kind, key, rect) { activate(token(kind, key, rect)); }
}
