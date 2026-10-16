import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtTest
import ".."

Item {
    id: scene
    width: 700; height: 800
    property int edits: 0
    Item {
        id: host
        width: scene.width
        property string settingsSectionQuery: ""
        ColumnLayout {
            width: parent.width
            SettingsCard {
                id: first
                Layout.fillWidth: true
                title: "Hyprdock"
                collapseThreshold: 100
                subtitle: "Panel controls"
                TextField { id: field; Layout.fillWidth: true; text: "unsaved name"; onTextEdited: scene.edits++ }
                SettingsSlider { id: slider; Layout.fillWidth: true; label: "Dock icon size"; settingValue: 24; from: 8; to: 96; onEdited: scene.edits++ }
            }
            SettingsCard {
                id: second
                Layout.fillWidth: true
                title: "Hyprbar"
                collapseThreshold: 60
                SettingsSwitch { id: toggle; text: "Show system items"; checked: true; onToggled: scene.edits++ }
            }
        }
    }
    SettingsCard {
        id: review
        visible: false
        title: "Review outside settings pages"
        TextField { text: "Review details" }
    }
    TestCase {
        name: "SettingsCard"; when: windowShown
        function init() {
            host.settingsSectionQuery="";
            first.collapseThreshold=100; second.collapseThreshold=60;
            first.expanded=Qt.binding(() => !first.longSection);
            second.expanded=Qt.binding(() => !second.longSection);
            field.text="unsaved name"; scene.edits=0;
            host.width=scene.width; wait(20);
        }
        function header(card) { return findChild(card,"settingsSectionHeader"); }
        function test_collapsedByDefaultAndIndependent() {
            verify(first.collapsible); verify(second.collapsible);
            verify(!first.contentExpanded); verify(!second.contentExpanded);
            verify(!field.visible); verify(!toggle.visible);
            let compactHeight=first.height;
            mouseClick(header(first)); wait(20);
            verify(first.contentExpanded); verify(field.visible);
            verify(first.height>compactHeight); verify(!second.contentExpanded);
            field.text="keep this draft";
            mouseClick(header(first)); wait(20);
            verify(!field.visible); compare(first.height,compactHeight);
            mouseClick(header(first)); compare(field.text,"keep this draft");
            compare(scene.edits,0);
        }
        function test_onlyLongSectionsStartCollapsed() {
            verify(first.longSection); verify(!first.contentExpanded);
            first.collapseThreshold=900;
            verify(!first.longSection); verify(first.contentExpanded);
            first.collapseThreshold=100;
            verify(first.longSection); verify(!first.contentExpanded);
            first.collapseThreshold=900;
            field.forceActiveFocus(); wait(10);
            first.collapseThreshold=100;
            verify(first.longSection); verify(first.contentExpanded);
            mouseClick(header(first)); verify(!first.contentExpanded);
            first.collapseThreshold=900; verify(!first.contentExpanded);
        }
        function test_keyboardAndFocus() {
            let heading=header(first);
            heading.forceActiveFocus(); keyClick(Qt.Key_Space); wait(20);
            verify(first.contentExpanded);
            field.forceActiveFocus(); keyClick(Qt.Key_A);
            compare(scene.edits,1);
            mouseClick(heading); verify(!first.contentExpanded); verify(heading.activeFocus);
            keyClick(Qt.Key_Tab); verify(header(second).activeFocus);
            keyClick(Qt.Key_Return); verify(second.contentExpanded);
        }
        function test_searchOpensHeadingAndHiddenControl() {
            host.settingsSectionQuery="hyprbar";
            verify(second.contentExpanded); verify(!first.contentExpanded);
            second.expanded=false; verify(!second.contentExpanded);
            host.settingsSectionQuery="  DOCK   ICON SIZE  ";
            verify(first.contentExpanded);
            host.settingsSectionQuery="";
            compare(scene.edits,0);
            verify(!review.collapsible); verify(review.contentExpanded);
        }
        function test_narrowHeadingAndExpandedBody() {
            for(let width of [360,660]) {
                host.width=width; first.expanded=true; wait(20);
                verify(header(first).width<=width);
                let point=field.mapToItem(first,0,0);
                verify(point.x>=0 && point.x+field.width<=first.width+1);
                first.expanded=false; wait(20); verify(first.height<80);
            }
        }
    }
}
