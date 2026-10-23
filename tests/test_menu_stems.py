"""Check shortcut menu stems with the production Hyprpane connection binding."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MenuStemTests(unittest.TestCase):
    def test_only_shown_items_have_stems(self):
        shell = (ROOT / 'config/quickshell/shell.qml').read_text()
        binding = re.search(r'^\s*connected: (.+)$', shell, re.MULTILINE).group(1)
        alignment = re.search(r'^\s*alignment: (.+)$', shell, re.MULTILINE).group(1)
        follow = re.search(r'^\s*alignToTrigger: (.+)$', shell, re.MULTILINE).group(1)
        trigger = shell.split('                triggerRect: {', 1)[1].split('\n                }', 1)[0]
        source = '''import QtQuick
import QtTest
import "IMPORT"
Item {
    id: scene
    width: 1366; height: 900
    Item {
        id: panel
        property real originX: bar.x
        property real originY: bar.y
        property var screen: ({width:scene.width,height:scene.height})
    }
    MenuController { id: menuState }
    Bar {
        id: bar
        width: vertical ? implicitWidth : scene.width
        x: position === "right" ? scene.width - width : 0
        y: position === "bottom" ? scene.height - height : 0
        statusData: ({workspaces:[{id:1,name:"1",active:true}], audio:{icon:"󰕾",text:"64%"}, network:{text:"󰤨"}, bluetooth:{text:"󰂯"}, battery:{present:true,text:"󰁹 86%"}})
        mediaData: ({playing:true,title:"Track",levels:[1,0.5]})
        previewWorkspaceId: 1
        clockText: "12:34"
    }
    MenuPopover {
        id: popover
        anchors.fill: parent
        instant: true
        opened: menuState.section.length > 0
        connected: BINDING
        alignment: ALIGNMENT
        alignToTrigger: FOLLOW
        triggerRect: { TRIGGER }
        edge: connected ? bar.position : "top"
        requestedBodyHeight: 200
    }
    TestCase {
        name: "MenuStems"
        when: windowShown
        function test_shortcuts_data() {
            let rows = [];
            for (let edge of ["top","bottom","left","right"])
                for (let menu of ["launcher","settings","audio","wifi","bluetooth","notifications","battery","power","calendar","workspacePreview","media"])
                    rows.push({tag:edge + "-" + menu,edge:edge,menu:menu});
            return rows;
        }
        function test_centeredMenusFollowIcons_data() {
            return test_shortcuts_data().filter(row => row.menu !== "launcher");
        }
        function test_centeredMenusFollowIcons(data) {
            menuState.close(); panel.visible = true;
            menuState.activate(data.menu,true);
            for (let background of ["on","off"]) {
                for (let padding of [0,45]) {
                    bar.settings = {bar:{position:data.edge,centerItems:true,background:background,
                        contentPaddingLeft:padding,contentPaddingRight:padding}};
                    wait(0);
                    verify(popover.alignToTrigger);
                    let trigger = bar.menuAnchorRect(data.menu);
                    fuzzyCompare(popover.triggerRect.x,trigger.x + bar.x,0.01);
                    fuzzyCompare(popover.triggerRect.y,trigger.y + bar.y,0.01);
                    let expected = popover.vertical
                        ? popover.clamp(popover.triggerRect.y + popover.triggerRect.height/2 - popover.bodyHeight/2,popover.safeTop,popover.safeBottom-popover.bodyHeight)
                        : popover.clamp(popover.triggerRect.x + popover.triggerRect.width/2 - popover.bodyWidth/2,popover.safeLeft,popover.safeRight-popover.bodyWidth);
                    fuzzyCompare(popover.vertical ? popover.bodyY : popover.bodyX,expected,0.01);
                    verify(popover.bodyX >= popover.safeLeft && popover.bodyRight <= popover.safeRight + 0.01);
                    verify(popover.bodyY >= popover.safeTop && popover.bodyBottom <= popover.safeBottom + 0.01);
                }
            }
            bar.settings = {bar:{position:data.edge,centerItems:false}};
            verify(!popover.alignToTrigger);
            panel.visible = false;
            verify(!popover.alignToTrigger);
        }
        function test_shortcuts(data) {
            menuState.close();
            panel.visible = true;
            let id = bar.menuItemId(data.menu);
            bar.settings = {bar:{position:data.edge}};
            menuState.activate(data.menu, true);
            verify(menuState.openedByShortcut);
            verify(popover.opened);
            verify(popover.connected, "Shown item keeps its stem");
            verify(findChild(popover,"menuFunnel").visible);
            for (let entry of [{enabled:false},{hideText:true,hideIcon:true},{opacity:0}]) {
                bar.settings = {bar:{position:data.edge},items:[Object.assign({id:id},entry)]};
                verify(popover.opened, "Hidden item remains accessible by shortcut");
                verify(!popover.connected, "Hidden item must have no stem");
                verify(!findChild(popover,"menuFunnel").visible);
            }
            bar.settings = {bar:{position:data.edge}};
            verify(popover.connected);
            panel.visible = false;
            verify(!popover.connected, "Hidden panel must have no stem");
            verify(!findChild(popover,"menuFunnel").visible);
            panel.visible = true;
            if (data.menu === "battery") {
                bar.statusData = Object.assign({},bar.statusData,{battery:{present:false}});
                verify(!popover.connected, "Absent battery must have no stem");
                bar.statusData = Object.assign({},bar.statusData,{battery:{present:true,text:"󰁹 86%"}});
            }
            if (data.menu === "media") {
                bar.mediaData = Object.assign({},bar.mediaData,{playing:false});
                verify(!popover.connected, "Inactive media must have no stem");
                bar.mediaData = Object.assign({},bar.mediaData,{playing:true});
            }
        }
    }
}'''.replace('IMPORT', (ROOT / 'config/quickshell').as_uri()).replace('BINDING', binding).replace('ALIGNMENT', alignment).replace('FOLLOW', follow).replace('TRIGGER', trigger)
        runner = subprocess.check_output(
            [sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'tst_MenuStems.qml'
            fixture.write_text(source)
            env = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run([runner, '-input', str(fixture)], env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
