import QtQuick

Item {
    id: controller
    property string section: ""
    // Keep the last menu's geometry and contents through its exit animation.
    property string displayedSection: ""
    onSectionChanged: if (section.length) displayedSection = section
    property string hoveredMenu: ""
    property bool hoverEnabled: true
    onHoverEnabledChanged: {
        openDelay.stop();
        hoveredMenu = "";
        if (!hoverEnabled && !pinned) close();
    }
    property bool pinned: false
    property bool openedByShortcut: false
    property bool dismissPinnedOnLeave: false
    property bool pointerInMenu: false
    readonly property bool keyboardPowerMenu: pinned && openedByShortcut && section === "power"

    function hover(name) {
        hoveredMenu = name;
        closeDelay.stop();
        if (hoverEnabled && section !== name) openDelay.restart();
    }
    function leave(name) {
        if (hoveredMenu !== name) return;
        hoveredMenu = "";
        openDelay.stop();
        retain(pointerInMenu);
    }
    function retain(inside) {
        pointerInMenu = inside;
        if (inside || hoveredMenu.length || keyboardPowerMenu || (pinned && !dismissPinnedOnLeave)) closeDelay.stop();
        else if (section.length) closeDelay.restart();
    }
    function activate(name, fromShortcut) {
        openDelay.stop();
        closeDelay.stop();
        if (section === name && pinned) close();
        else {
            openedByShortcut = fromShortcut === true;
            section = name;
            pinned = true;
        }
    }
    function close() {
        openDelay.stop();
        closeDelay.stop();
        section = "";
        pinned = false;
        openedByShortcut = false;
    }
    Timer {
        id: openDelay
        interval: 110
        onTriggered: {
            if (!controller.hoverEnabled || !controller.hoveredMenu.length) return;
            if (controller.section !== controller.hoveredMenu) {
                controller.pinned = false;
                controller.openedByShortcut = false;
            }
            controller.section = controller.hoveredMenu;
        }
    }
    Timer {
        id: closeDelay
        interval: 320
        onTriggered: {
            if (!controller.pointerInMenu && !controller.hoveredMenu.length && !controller.keyboardPowerMenu && (!controller.pinned || controller.dismissPinnedOnLeave))
                controller.close();
        }
    }
}
