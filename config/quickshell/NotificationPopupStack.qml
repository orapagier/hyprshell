pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: view
    required property var inbox
    property var expandedIds: []
    property var hoveredIds: []
    function updateHeld() { view.inbox.heldPopupIds = Array.from(new Set(expandedIds.concat(hoveredIds))); }
    onExpandedIdsChanged: updateHeld()
    onHoveredIdsChanged: updateHeld()
    function setHovered(id, hovered) {
        hoveredIds = hoveredIds.filter(value => value !== id);
        if (hovered) hoveredIds = hoveredIds.concat([id]);
    }
    function toggleExpanded(id) {
        expandedIds = expandedIds.includes(id) ? expandedIds.filter(value => value !== id) : expandedIds.concat([id]);
    }
    Connections {
        target: view.inbox
        function onPopupsChanged() {
            view.hoveredIds = [];
            view.expandedIds = view.expandedIds.filter(id => view.inbox.popups.some(row => row.id === id));
        }
    }
    implicitHeight: stack.implicitHeight
    ColumnLayout {
        id: stack
        anchors.left: parent.left; anchors.right: parent.right
        spacing: 10
        Repeater {
            model: view.inbox.popups
            delegate: Rectangle {
                id: toast
                required property var modelData
                readonly property bool expanded: view.expandedIds.includes(modelData.id)
                readonly property bool held: expanded || hover.hovered
                objectName: "popup-" + modelData.id
                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + 32
                radius: 16
                color: "#202332"
                border.color: modelData.critical ? "#f38ba8" : "#45495f"
                MouseArea {
                    anchors.fill: parent
                    onClicked: view.toggleExpanded(toast.modelData.id)
                }
                HoverHandler { id: hover; onHoveredChanged: view.setHovered(toast.modelData.id, hovered) }
                Timer {
                    interval: Math.max(1, toast.modelData.popupDeadline - Date.now())
                    running: !toast.modelData.critical && !toast.held
                    onTriggered: view.inbox.hidePopup(toast.modelData.id)
                }
                ColumnLayout {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: toast.modelData.critical ? "#f38ba8" : "#cba6f7"
                        }
                        Label {
                            Layout.fillWidth: true
                            text: (toast.modelData.critical ? "Critical · " : "") + toast.modelData.app
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "#a6adc8"
                            font.pixelSize: 11
                            TapHandler { onTapped: view.toggleExpanded(toast.modelData.id) }
                        }
                        MenuButton {
                            objectName: "popupClose"
                            implicitWidth: 26; implicitHeight: 26
                            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                            text: "×"
                            font.pixelSize: 20
                            Accessible.name: "Close popup, keep in inbox"
                            contentItem: Text {
                                text: "×"; color: "#a6adc8"; font.pixelSize: 20
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { radius: 8; color: parent.hovered ? "#20ffffff" : "transparent" }
                            onClicked: view.inbox.hidePopup(toast.modelData.id)
                        }
                    }
                    ScrollView {
                        id: details
                        objectName: "popupDetails"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(textContent.implicitHeight, toast.expanded ? 320 : 180)
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: toast.expanded ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        ColumnLayout {
                            id: textContent
                            width: details.availableWidth
                            spacing: 8
                            Label {
                                objectName: "popupSummary"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: toast.modelData.summary
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: toast.expanded ? 2147483647 : 2
                                elide: toast.expanded ? Text.ElideNone : Text.ElideRight
                                color: "#ecebff"
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Label {
                                objectName: "popupBody"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: text.length > 0
                                text: toast.modelData.body
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: toast.expanded ? 2147483647 : 3
                                elide: toast.expanded ? Text.ElideNone : Text.ElideRight
                                color: "#bac2de"
                                font.pixelSize: 13
                            }
                            TapHandler { onTapped: view.toggleExpanded(toast.modelData.id) }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: toast.expanded ? "Click to collapse" : "Click to expand"
                        color: "#9399b2"
                        font.pixelSize: 10
                        TapHandler { onTapped: view.toggleExpanded(toast.modelData.id) }
                    }
                    Repeater {
                        model: toast.modelData.active ? (toast.modelData.actions || []).filter(action => (action.text || "").trim().length > 0) : []
                        delegate: MenuButton {
                            required property var modelData
                            objectName: "popupAction-" + modelData.id
                            Layout.fillWidth: true
                            text: modelData.text
                            onClicked: { view.inbox.invoke(toast.modelData.id, modelData.id); view.inbox.hidePopup(toast.modelData.id); }
                        }
                    }
                }
            }
        }
    }
}
