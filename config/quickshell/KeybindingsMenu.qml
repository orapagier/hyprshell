pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.Window

ColumnLayout {
    id: page
    QtObject {
        id: theme
        readonly property color windowText: "#e2e6f3"
        readonly property color text: windowText
        readonly property color highlight: "#b4befe"
        readonly property color highlightedText: "#161824"
        readonly property color base: "#161824"
    }
    readonly property var powerShortcuts: [
        {shortcut: "Alt + P + L", action: "Lock screen"},
        {shortcut: "Alt + P + X", action: "Shutdown"},
        {shortcut: "Alt + P + R", action: "Reboot"},
        {shortcut: "Alt + P + S", action: "Sleep"},
        {shortcut: "Alt + P + O", action: "Logout"}
    ]
    property var bindings: []
    property string error: ""
    readonly property var entries: bindings.concat(powerShortcuts).filter(b => {
        let haystack = (b.shortcut + " " + b.action).toLowerCase();
        return search.text.toLowerCase().trim().split(/\s+/).every(word => haystack.includes(word));
    })
    spacing: 12
    function shortcut(binding) {
        let parts = [];
        for (let modifier of [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]])
            if (binding.modmask & modifier[0]) parts.push(modifier[1]);
        let key = binding.key || (binding.keycode ? "Keycode " + binding.keycode : "Unknown key");
        key = ({"Super_L":"Super", "mouse:272":"Left mouse", "mouse:273":"Right mouse", "mouse_down":"Scroll down", "mouse_up":"Scroll up"})[key] || key;
        parts.push(key.length === 1 ? key.toUpperCase() : key);
        return parts.join(" + ");
    }
    Timer { interval: 1500; running: true; repeat: true; onTriggered: if (!bindingReader.running) bindingReader.running = true }
    Process {
        id: bindingReader
        command: ["hyprctl", "-j", "binds"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.error = "";
                    page.bindings = JSON.parse(text).map(b => ({
                        shortcut: page.shortcut(b),
                        action: b.description || [b.dispatcher, b.arg].filter(Boolean).join(" ") || "Custom action"
                    })).sort((a, b) => a.shortcut.localeCompare(b.shortcut));
                } catch (e) { page.error = "Could not load keybindings"; }
            }
        }
        onExited: (code, status) => { if (code !== 0) page.error = "Could not load keybindings"; }
    }
    TextField {
        id: search
        Layout.fillWidth: true
        implicitHeight: 46
        leftPadding: 15; rightPadding: 15
        placeholderText: "Search an action or key combination…"
        color: theme.text
        placeholderTextColor: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.45)
        font.family: "Noto Sans"; font.pixelSize: 13
        selectionColor: theme.highlight
        selectedTextColor: theme.highlightedText
        background: Rectangle {
            radius: 12
            color: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.65)
            border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.12)
            Behavior on border.color { ColorAnimation { duration: 140 } }
        }
        Component.onCompleted: forceActiveFocus()
        onTextChanged: list.currentIndex = 0
        Keys.onDownPressed: { list.forceActiveFocus(); list.currentIndex = 0; }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true; Layout.minimumHeight: 120
        model: page.entries
        clip: true; spacing: 6
        keyNavigationEnabled: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool highlighted: hover.hovered || (list.activeFocus && list.currentIndex === index)
            width: list.width
            height: labels.implicitHeight + 24
            radius: 12
            color: highlighted ? Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.12) : Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.035)
            border.color: highlighted ? Qt.rgba(theme.highlight.r, theme.highlight.g, theme.highlight.b, 0.24) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: hover }
            Column {
                id: labels
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                spacing: 9
                Text {
                    width: parent.width; text: row.modelData.action
                    color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 13; font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
                Flow {
                    width: parent.width; spacing: 5
                    Repeater {
                        model: row.modelData.shortcut.split(" + ")
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: keyLabel.implicitWidth + 14
                            implicitHeight: 24; radius: 6
                            color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.065)
                            border.color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.10)
                            Text { id: keyLabel; anchors.centerIn: parent; text: modelData; color: theme.windowText; opacity: 0.78; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }
        Column {
            anchors.centerIn: parent; width: parent.width; spacing: 8
            visible: !page.entries.length
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error || "No shortcuts found"; color: theme.windowText; font.family: "Noto Sans"; font.pixelSize: 14; font.weight: Font.Medium }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: page.error ? "Try opening the panel again" : "Try a different action or key"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 12 }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(theme.windowText.r, theme.windowText.g, theme.windowText.b, 0.08) }
    RowLayout {
        Layout.fillWidth: true
        Text { text: page.entries.length + " shortcuts"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: "↑ ↓  Browse   ·   Esc  Close"; color: theme.windowText; opacity: 0.55; font.family: "Noto Sans"; font.pixelSize: 11 }
    }
}
