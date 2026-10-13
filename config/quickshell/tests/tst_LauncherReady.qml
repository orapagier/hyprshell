import QtQuick
import QtTest
import ".."

Item {
    width: 600; height: 600
    MenuPopover {
        id: popover
        anchors.fill: parent
        persistentPage: readyPage
        persistentSelected: true
        instant: true
        page: otherPage
    }
    Component { id: readyPage; Item { implicitHeight: 300; property string query: "" } }
    Component { id: otherPage; Item { implicitHeight: 100 } }
    TestCase {
        name: "LauncherReady"
        when: windowShown
        function test_keepsPreparedPageAcrossCloseAndMenuSwitch() {
            let launcher = popover.pageItem;
            verify(launcher !== null);
            launcher.query = "retained state";
            popover.opened = true;
            compare(popover.rendering, true);
            popover.opened = false;
            compare(popover.rendering, false);
            compare(popover.pageItem, launcher);
            popover.persistentSelected = false;
            popover.opened = true;
            verify(popover.pageItem !== launcher);
            popover.opened = false;
            popover.persistentSelected = true;
            compare(popover.pageItem, launcher);
            compare(launcher.query, "retained state");
            popover.opened = true;
            compare(popover.rendering, true);
            popover.opened = false;
        }
    }
}
