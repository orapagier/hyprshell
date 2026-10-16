pragma ComponentBehavior: Bound
import QtQuick
import "SettingsModel.js" as Model

Item {
    id: editor
    required property var bar
    property var names: ({})
    property string draggedId: ""
    property bool dragging: false
    property real pressX: 0
    property real pressY: 0
    property real pointerX: 0
    property real pointerY: 0
    property var destination: ({side:"left", beforeId:"", markerX:0})
    signal itemSelected(string id)
    signal itemDropped(string id, string side, string beforeId)
    z: 10

    function itemAt(x, y) {
        return Object.keys(bar.moduleItems).find(id => {
            let item = bar.moduleItems[id], rect = bar.itemRect(id);
            return item.visible && x >= rect.x && x <= rect.x + rect.width && y >= rect.y && y <= rect.y + rect.height;
        }) || "";
    }
    function dropAt(x, y) {
        let hoveredId = itemAt(x, y);
        let cursor = bar.vertical ? y : x, length = bar.vertical ? height : width;
        let start = item => bar.vertical ? item.y - bar.scrollOffset : item.x;
        let size = item => bar.vertical ? item.height : item.width;
        let side = hoveredId ? bar.side(hoveredId) : cursor < length / 3 ? "left" : cursor > length * 2 / 3 ? "right" : "center";
        let group = Object.keys(bar.moduleItems).filter(id => id !== draggedId && bar.moduleItems[id].visible && bar.side(id) === side)
            .sort((a, b) => start(bar.moduleItems[a]) - start(bar.moduleItems[b]));
        let before = group.find(id => cursor < start(bar.moduleItems[id]) + size(bar.moduleItems[id]) / 2);
        let last = group.length ? bar.moduleItems[group[group.length - 1]] : null;
        return {side:side, beforeId:before || "", markerX:before ? start(bar.moduleItems[before]) - 2 : last ? start(last) + size(last) + 2 : side === "left" ? 2 : side === "right" ? length - 2 : length / 2};
    }
    // This overlay captures gestures only in the settings preview.
    MouseArea {
        id: pointer
        objectName: "previewDragArea"
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: editor.dragging ? Qt.ClosedHandCursor : editor.itemAt(mouseX, mouseY) ? Qt.OpenHandCursor : Qt.ArrowCursor
        onPressed: mouse => {
            editor.draggedId = editor.itemAt(mouse.x, mouse.y);
            editor.pressX = mouse.x;
            editor.pressY = mouse.y;
            editor.pointerX = mouse.x;
            editor.pointerY = mouse.y;
        }
        onPositionChanged: mouse => {
            if (!pressed || !editor.draggedId) return;
            if (Math.abs(mouse.x-editor.pressX) + Math.abs(mouse.y-editor.pressY) >= 6)
                editor.dragging = true;
            editor.pointerX = mouse.x;
            editor.pointerY = mouse.y;
            editor.destination = editor.dropAt(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            if (editor.draggedId) {
                if (editor.dragging && mouse.x >= 0 && mouse.x <= width && mouse.y >= 0 && mouse.y <= height) {
                    let target = editor.dropAt(mouse.x, mouse.y);
                    editor.itemDropped(editor.draggedId, target.side, target.beforeId);
                } else if (!editor.dragging) {
                    editor.itemSelected(editor.draggedId);
                }
            }
            editor.dragging = false;
            editor.draggedId = "";
        }
        onWheel: event => { if (editor.bar.vertical) editor.bar.scrollVertical(event); else event.accepted = false; }
        onCanceled: { editor.dragging = false; editor.draggedId = ""; }
    }
    Rectangle {
        visible: editor.dragging
        x: editor.bar.vertical ? 1 : editor.destination.markerX - 1
        y: editor.bar.vertical ? editor.destination.markerX - 1 : 1
        width: editor.bar.vertical ? editor.width - 2 : 2
        height: editor.bar.vertical ? 2 : editor.height - 2
        color: "#d1b5ff"
        radius: 1
    }
    Rectangle {
        visible: editor.dragging
        x: Math.max(0, Math.min(editor.width-width, editor.pointerX-width/2))
        y: editor.bar.vertical ? Math.max(0, Math.min(editor.height - height, editor.pointerY)) : editor.height + 4
        width: caption.implicitWidth + 24; height: 28
        radius: 10; color: "#35304e"; border.color: "#b99ce4"
        Text {
            id: caption
            anchors.centerIn: parent
            text: (editor.names[editor.draggedId] || editor.draggedId) + " → " + (editor.bar.vertical ? ({left:"top",center:"center",right:"bottom"})[editor.destination.side] : editor.destination.side)
            color: "#eee4ff"; font.pixelSize: 11
        }
    }
}
