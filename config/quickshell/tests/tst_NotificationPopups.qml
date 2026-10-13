import QtQuick
import QtTest
import ".."

Item {
    id: root
    width: 400; height: 700
    QtObject {
        id: inbox
        property var popups: []
        property var heldPopupIds: []
        property int unread: 1
        function holdPopup(id, held) {
            heldPopupIds = heldPopupIds.filter(value => value !== id);
            if (held) heldPopupIds = heldPopupIds.concat([id]);
        }
        function hidePopup(id) { popups = popups.filter(row => row.id !== id); }
        function invoke(id, action) {}
    }
    NotificationPopupStack { id: stack; width: 380; inbox: root.store }
    readonly property var store: inbox
    TestCase {
        name: "NotificationPopups"
        when: windowShown
        function init() {
            inbox.popups = [{id: "long", app: "Example app", summary: "Full notification details", body: Array(100).fill("More details to read and scroll through.").join("\n") + "\nFINAL LINE", active: true, actions: [{id: "blank", text: " "}, {id: "open", text: "Open"}], popupDeadline: Date.now() + 1000}];
            waitForRendering(stack);
        }
        function cleanup() { inbox.popups = []; }
        function test_expandScrollAndCloseRetainsUnread() {
            let toast = findChild(stack, "popup-long");
            let body = findChild(toast, "popupBody");
            let scroll = findChild(toast, "popupDetails");
            compare(toast.expanded, false);
            verify(body.truncated);
            verify(findChild(toast, "popupAction-blank") === null);
            verify(findChild(toast, "popupAction-open") !== null);
            mouseClick(body, 30, 10);
            tryCompare(toast, "expanded", true);
            waitForRendering(stack);
            verify(inbox.heldPopupIds.includes("long"));
            // Rebuilding the stack for another alert must preserve expansion.
            inbox.popups = inbox.popups.slice();
            waitForRendering(stack);
            toast = findChild(stack, "popup-long");
            body = findChild(toast, "popupBody");
            scroll = findChild(toast, "popupDetails");
            verify(toast.expanded);
            verify(inbox.heldPopupIds.includes("long"));
            verify(!body.truncated);
            verify(body.text.endsWith("FINAL LINE"));
            verify(scroll.contentHeight > scroll.height);
            scroll.contentItem.contentY = scroll.contentHeight - scroll.height;
            waitForRendering(stack);
            let bottom = body.mapToItem(scroll.contentItem, 0, body.height);
            verify(bottom.y > 0 && bottom.y <= scroll.height + 1);
            // Reading past the original timeout must keep the popup open.
            wait(1200);
            compare(inbox.popups.length, 1);
            let saved = false;
            stack.grabToImage(result => { result.saveToFile("/tmp/hyprshell-popup-expanded.png"); saved = true; });
            tryVerify(() => saved);
            let close = findChild(toast, "popupClose");
            mouseClick(close, close.width / 2, close.height / 2);
            tryCompare(inbox, "popups", []);
            compare(inbox.unread, 1);
            compare(inbox.heldPopupIds.length, 0);
        }
    }
}
