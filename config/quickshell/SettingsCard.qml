import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

ColumnLayout {
    id: root
    required property string title
    property string subtitle: ""
    default property alias controls: body.data
    readonly property bool settingsSectionCard: true
    readonly property var sectionHost: {
        for (let item = parent; item; item = item.parent)
            if (item.settingsSectionQuery !== undefined) return item;
        return null;
    }
    property bool collapsible: sectionHost !== null
    readonly property real contentHeight: body.implicitHeight + 32
    property real collapseThreshold: 1000
    readonly property bool longSection: contentHeight > collapseThreshold
    property bool expanded: !longSection
    readonly property bool contentExpanded: !collapsible || expanded
    readonly property string searchQuery: sectionHost ? sectionHost.settingsSectionQuery.toLowerCase().replace(/\s+/g, " ").trim() : ""
    readonly property bool searchMatch: searchQuery.length > 0
        && (title.toLowerCase().includes(searchQuery) || matchesControl(body, searchQuery))
    onSearchMatchChanged: if (searchMatch) expanded = true
    Connections {
        id: focusObserver
        target: root.Window.window
        function onActiveFocusItemChanged() {
            // Once editing begins, keep the section open even if its rows grow.
            for (let item = target.activeFocusItem; item; item = item.parent)
                if (item === body) { root.expanded = true; return; }
        }
    }
    function matchesControl(item, query) {
        for (let key of ["title", "label", "text"]) {
            let caption = item[key];
            if (typeof caption === "string" && caption.toLowerCase().replace(/\s+/g, " ").includes(query)) return true;
        }
        for (let child of item.children || [])
            if (matchesControl(child, query)) return true;
        return false;
    }
    Layout.minimumWidth: 0
    spacing: 8
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 2
        ToolButton {
            id: heading
            objectName: "settingsSectionHeader"
            Layout.fillWidth: true
            implicitHeight: Math.max(30, contentItem.implicitHeight + topPadding + bottomPadding)
            leftPadding: 4; rightPadding: 6; topPadding: 2; bottomPadding: 2
            enabled: root.collapsible
            hoverEnabled: true
            activeFocusOnTab: root.collapsible
            Accessible.name: root.title
            Accessible.description: root.contentExpanded ? "Collapse section" : "Expand section"
            Accessible.checkable: root.collapsible
            Accessible.checked: root.contentExpanded
            onClicked: { forceActiveFocus(); root.expanded = !root.contentExpanded; }
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            contentItem: RowLayout {
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    text: root.title; color: Style.SettingsTheme.text
                    font.pixelSize: Style.SettingsTheme.sectionSize; font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Label {
                    visible: root.collapsible
                    text: "⌄"
                    rotation: root.contentExpanded ? 0 : -90
                    color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.sectionSize
                    Behavior on rotation { NumberAnimation { duration: Style.SettingsTheme.duration(root, 200); easing.type: Easing.OutCubic } }
                }
            }
            background: Rectangle {
                color: heading.hovered && root.collapsible ? Style.SettingsTheme.hover : "transparent"
                radius: Style.SettingsTheme.controlRadius
                border.color: heading.activeFocus ? Style.SettingsTheme.accentText : "transparent"
                border.width: heading.activeFocus ? 2 : 0
            }
        }
        Label { visible: root.contentExpanded && text !== ""; text: root.subtitle; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize }
    }
    Rectangle {
        visible: root.contentExpanded
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 32
        color: Style.SettingsTheme.card
        radius: Style.SettingsTheme.cardRadius
        border.color: Style.SettingsTheme.highContrast ? Style.SettingsTheme.border : "transparent"
        border.width: Style.SettingsTheme.highContrast ? 1 : 0
        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12
        }
    }
}
