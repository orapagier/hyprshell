import QtQuick
import QtTest
import ".."

Item {
    id: root
    property var received: []
    PowerShortcuts {
        id: shortcuts
        active: true
        onTriggered: key => root.received = root.received.concat([key])
    }
    Window {
        id: otherWindow
        width: 100; height: 100; visible: true
        TestCase {
            name: "PowerOverlayWindowFocus"
            when: windowShown
            function test_menuShortcutsDoNotDependOnActiveQtWindow() {
                otherWindow.requestActivate();
                tryVerify(() => otherWindow.active);
                keyClick(Qt.Key_L);
                tryCompare(root, "received", [Qt.Key_L]);
                shortcuts.active = false;
                keyClick(Qt.Key_X);
                compare(root.received.length, 1);
            }
        }
    }
}
