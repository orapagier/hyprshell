import QtQuick
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
    property bool expanded: false
    readonly property bool contentExpanded: !collapsible || expanded
    readonly property string searchQuery: sectionHost ? sectionHost.settingsSectionQuery.toLowerCase().replace(/\s+/g, " ").trim() : ""
    readonly property bool searchMatch: searchQuery.length > 0
        && (title.toLowerCase().includes(searchQuery) || matchesControl(body, searchQuery))
    onSearchMatchChanged: if (searchMatch) expanded = true
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
    spacing: 10
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        spacing: 4
        ToolButton {
            id: heading
            objectName: "settingsSectionHeader"
            Layout.fillWidth: true
            implicitHeight: Math.max(40, contentItem.implicitHeight + topPadding + bottomPadding)
            leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
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
                spacing: 10
                Label {
                    Layout.fillWidth: true
                    text: root.title; color: Style.Theme.text
                    font.pixelSize: Style.Theme.sectionSize; font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Label {
                    visible: root.collapsible
                    text: root.contentExpanded ? "⌄" : "›"
                    color: Style.Theme.accentText; font.pixelSize: Style.Theme.sectionSize
                }
            }
            background: Rectangle {
                color: heading.hovered && root.collapsible ? Style.Theme.hover : "transparent"
                radius: Style.Theme.controlRadius
                border.color: heading.activeFocus ? Style.Theme.accentText : "transparent"
                border.width: heading.activeFocus ? 2 : 0
            }
        }
        Label { visible: root.contentExpanded && text !== ""; text: root.subtitle; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize }
    }
    Rectangle {
        visible: root.contentExpanded
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 36
        color: Style.Theme.surface
        radius: Style.Theme.radius
        border.color: Style.Theme.separator
        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 16
        }
    }
}
