import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: control
    property string switchText: "Show background pill"
    property string mode: "inherit"
    property bool inheritedVisible: true
    property string inheritLabel: "Use general setting"
    property string inheritDescription: "Following general setting"
    signal edited(string mode)
    spacing: 6
    GridLayout {
        Layout.fillWidth: true
        columns: control.width >= 480 ? 2 : 1
        SettingsSwitch {
            Layout.fillWidth: true
            objectName: "backgroundPillSwitch"
            text: control.switchText
            checked: control.mode === "on" || (control.mode !== "off" && control.inheritedVisible)
            onToggled: control.edited(checked ? "on" : "off")
        }
        SettingsButton {
            text: control.inheritLabel
            enabled: control.mode !== "inherit"
            onClicked: control.edited("inherit")
        }
    }
    Label {
        Layout.fillWidth: true
        text: control.mode === "inherit" ? control.inheritDescription : control.mode === "on" ? "Background pill shown" : "Background pill removed"
        color: Style.Theme.muted
        font.pixelSize: Style.Theme.captionSize
        wrapMode: Text.WordWrap
    }
}
