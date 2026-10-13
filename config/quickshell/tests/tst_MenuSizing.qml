import QtQuick
import QtQuick.Layouts
import QtTest
import ".."

Item {
    width: 1000; height: 1000
    MenuPopover {
        id: menu
        anchors.fill: parent
        opened: true
        persistentPage: launcher
        persistentSelected: true
        page: other
    }
    Component {
        id: launcher
        ColumnLayout {
            Rectangle { implicitWidth: 200; implicitHeight: 30 }
            Item { Layout.preferredHeight: 300; Layout.fillWidth: true }
        }
    }
    Component { id: other; Item { implicitHeight: 600 } }
    TestCase {
        name: "MenuSizing"
        when: windowShown
        function test_launcherHeightStaysStableAfterOtherMenus() {
            wait(100);
            let initialHeight = menu.bodyHeight;
            verify(initialHeight > 300 && initialHeight < 600);
            for (let i = 0; i < 5; i++) {
                menu.persistentSelected = false;
                wait(50);
                verify(menu.bodyHeight > initialHeight);
                menu.persistentSelected = true;
                wait(50);
                compare(menu.bodyHeight, initialHeight);
            }
        }
    }
}
