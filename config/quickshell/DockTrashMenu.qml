pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: menu
    required property var utilities
    property bool active: true
    property bool confirming: false
    onActiveChanged: if (!active) confirming = false
    spacing: 10
    Text {
        Layout.fillWidth: true
        text: menu.confirming ? 'Permanently delete every item in Trash? This cannot be undone.'
            : !menu.utilities.available ? 'Trash status unavailable' : menu.utilities.full ? 'Trash contains deleted files' : 'Trash is empty'
        color: '#cdd6f4'; wrapMode: Text.Wrap
    }
    MenuButton { Layout.fillWidth:true; text:'Open Trash'; enabled:!menu.utilities.busy; onClicked:menu.utilities.run('trash') }
    MenuButton {
        objectName:'dockEmptyTrash'
        Layout.fillWidth:true
        text:menu.confirming ? 'Confirm empty Trash' : 'Empty Trash…'
        enabled:!menu.utilities.busy && menu.utilities.available && menu.utilities.full
        onClicked: {
            if (!menu.confirming) menu.confirming = true;
            else { menu.utilities.run('empty-confirmed'); menu.confirming = false; }
        }
    }
    MenuButton { Layout.fillWidth:true; text:'Cancel'; visible:menu.confirming; onClicked:menu.confirming = false }
    Text { Layout.fillWidth:true; visible:!!menu.utilities.error; text:menu.utilities.error; color:'#f38ba8'; wrapMode:Text.Wrap }
}
