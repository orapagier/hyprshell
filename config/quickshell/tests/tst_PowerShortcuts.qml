import QtQuick
import QtQuick.Controls
import QtTest
import ".."

Item {
    id: root
    width: 320; height: 200
    property var received: []
    Button { id: button; text: "Focused menu button"; focus: true }
    PowerShortcuts {
        id: shortcuts
        active: true
        onTriggered: key => root.received = root.received.concat([key])
    }
    TestCase {
        name: "PowerShortcuts"
        when: windowShown
        function init() {
            root.received = [];
            shortcuts.active = true;
            button.forceActiveFocus();
        }
        function test_actionsWithButtonFocus_data() {
            return [Qt.Key_L, Qt.Key_X, Qt.Key_R, Qt.Key_S, Qt.Key_O].map(key => ({tag: String(key), key: key}));
        }
        function test_actionsWithButtonFocus(data) {
            keyClick(data.key);
            tryCompare(root, "received", [data.key]);
        }
        function test_altMayRemainHeld() {
            keyClick(Qt.Key_L, Qt.AltModifier);
            tryCompare(root, "received", [Qt.Key_L]);
        }
        function test_inactiveMenuDoesNotHandleKeys() {
            shortcuts.active = false;
            keyClick(Qt.Key_X);
            keyClick(Qt.Key_L, Qt.AltModifier);
            compare(root.received.length, 0);
        }
        function test_unrelatedModifiersDoNotRunActions() {
            keyClick(Qt.Key_X, Qt.ControlModifier);
            keyClick(Qt.Key_X, Qt.MetaModifier);
            keyClick(Qt.Key_X, Qt.ShiftModifier);
            compare(root.received.length, 0);
        }
    }
}
