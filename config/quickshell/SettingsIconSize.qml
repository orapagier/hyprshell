import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: control
    property bool individual: false
    property var settingValue: 0
    property int inheritedSize: 0
    signal edited(var value)
    SettingsSlider {
        Layout.fillWidth: true
        label: control.individual ? "Size for this item" : "Size for all items"
        from: 8; to: 48; suffix: " px"
        settingValue: control.settingValue > 0 ? control.settingValue : undefined
        inheritedText: control.individual ? "Use global" : "80% of own pill"
        defaultValue: control.inheritedSize || 16
        resetDescription: control.individual ? "Use the global item size" : "Follow 80% of each item pill"
        description: control.individual ? "Resize this item's icons and text together. ↺ follows the global size. A custom text size takes priority." : "Resize icons and text together, including workspaces, the clock, tray artwork, and the media spectrum. Individual sizes take priority. The bar grows to fit."
        onEdited: value => control.edited(value === "" ? 0 : value)
    }
}
