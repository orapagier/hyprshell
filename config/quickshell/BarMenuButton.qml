import QtQuick
import QtQuick.Controls.Basic
import "SettingsModel.js" as Settings

Pill {
    id: control
    required property var bar
    required property string menu
    iconOnlyHeight: bar.verticalThickness - 4
    iconOnly: bar.iconsOnly || (bar.statusIconsOnly && menu !== "calendar")
    implicitHeight: bar.panelSlotSize
    objectName: menu + "Trigger"
    colorSampler: Settings.adaptive(bar.settings, menu) ? bar.wallpaperColors : null
    colorRoot: bar
    width: vertical ? bar.panelSlotSize : implicitWidth
    height: vertical ? width : implicitHeight
    compactIcon: {
        if ((menu === "launcher" || menu === "settings") && !settings.text && !settings.icon) return "";
        return ({launcher:"", settings:"󰒓", calendar:"󰃭", notifications:"󰂚",
            audio:bar.statusData.audio?.icon || "󰕾", wifi:bar.statusData.network?.text || "󰤮",
            bluetooth:bar.statusData.bluetooth?.text || "󰂲", battery:icon || "󰁹", power:"󰐥"})[menu] || icon;
    }
    onActiveFocusChanged: if (activeFocus) bar.ensureItemVisible(control)
    onWheel: event => { if (vertical) bar.scrollVertical(event); }
    selected: bar.activeMenu === menu
    onEntered: bar.menuHovered(menu)
    onExited: bar.menuLeft(menu)
    onClicked: bar.action(menu, null)
}
