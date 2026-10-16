import QtQuick
import QtQuick.Controls.Basic
import "SettingsModel.js" as Settings

Pill {
    id: control
    required property var bar
    required property string menu
    objectName: menu + "Trigger"
    colorSampler: Settings.adaptive(bar.settings, menu) ? bar.wallpaperColors : null
    colorRoot: bar
    width: vertical ? bar.verticalThickness - 4 : implicitWidth
    height: vertical ? width : implicitHeight
    compactIcon: {
        if ((menu === "launcher" || menu === "settings") && !settings.text && !settings.icon) return "";
        return ({launcher:"", settings:"󰒓", calendar:"󰃭", notifications:"󰂚",
            audio:bar.statusData.audio?.icon || "󰕾", wifi:bar.statusData.network?.text || "󰤮",
            bluetooth:bar.statusData.bluetooth?.text || "󰂲", battery:icon || "󰁹", power:"󰐥"})[menu] || icon;
    }
    property string tooltipText: {
        let title = ({launcher: "Applications", settings: "Settings", calendar: "Calendar", notifications: "Notifications", audio: "Volume", wifi: "Network", bluetooth: "Bluetooth", battery: "Battery", power: "Power"})[menu] || menu;
        let detail = settings.text || text;
        if (menu === "calendar") detail = settings.text || bar.clockText;
        else if (menu === "notifications") detail = bar.notificationData?.tooltip || String(bar.notificationData?.count || 0);
        else if (menu === "wifi") detail = bar.statusData.network?.tooltip || detail;
        else if (menu === "bluetooth") detail = bar.statusData.bluetooth?.tooltip || detail;
        else if (menu === "battery") detail = bar.statusData.battery?.tooltip || detail;
        return title + (detail ? " · " + detail : "");
    }
    ToolTip.visible: vertical && hovered
    ToolTip.text: tooltipText
    ToolTip.delay: 600
    onActiveFocusChanged: if (activeFocus && vertical) bar.ensureItemVisible(control)
    onWheel: event => { if (vertical) bar.scrollVertical(event); }
    selected: bar.activeMenu === menu
    onEntered: bar.menuHovered(menu)
    onExited: bar.menuLeft(menu)
    onClicked: bar.action(menu, null)
}
