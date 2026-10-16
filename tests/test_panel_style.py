"""Native four-edge visual regression for the common Hyprpane pill styling."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'config/quickshell'


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class PanelStyleTests(unittest.TestCase):
    def test_shared_pill_and_narrow_sides(self):
        source = '''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "PAYLOAD"
import "PAYLOAD/SettingsModel.js" as Settings
ShellRoot {
    id:test
    SettingsStore { id:store }
    property var config:store.config
    property var rows:Array.from({length:6},(_,i)=>({key:'app:'+i,id:'app'+i+'.desktop',name:'Application '+i,
        installed:true,pinned:i<2,active:i===3,icon:['brave-browser','org.gnome.Nautilus','kitty'][i%3],
        windows:[{address:'ab'+i,title:'Window '+i,workspace:1,output:'eDP-1'}]}))
    AppIcons { id:icons;visible:false }
    QtObject {
        id:service
        property bool busy:false
        function groups(component) { return test.rows; }
        function iconSource(name) { return icons.source(name) || icons.source('application-x-executable'); }
        function edit(action) { return true; }
    }
    function edge(value) {
        let next=Settings.copy(test.config); next.panels.hyprbar.position=value;
        next.panels.hyprbar.verticalWidth=200; return next;
    }
    Window {
        id:window
        visible:true; width:1100; height:900; color:'#477491'
        Rectangle { anchors.fill:parent; gradient:Gradient { GradientStop {position:0;color:'#65acd0'} GradientStop {position:1;color:'#102b40'} } }
        Text { x:70;y:8;text:'Hyprpane reference';color:'white' }
        Bar { id:pane; x:70;y:30;width:960;height:32;settings:test.config;clockText:'October 16 · 07:15 PM';screenWidth:1100 }
        Text { x:70;y:80;text:'Hyprdock';color:'white' }
        Dock { id:dock; x:(1100-width)/2;y:103;component:'hyprdock';config:test.config;service:service;width:implicitWidth;height:implicitHeight }
        Text { x:70;y:158;text:'Hyprbar — one continuous pill';color:'white' }
        Dock { id:bar; x:70;y:184;component:'hyprbar';outputName:'eDP-1';config:test.config;service:service;maximumLength:960;
            width:implicitWidth;height:implicitHeight;trailingLength:status.contentLength+8 }
        TaskbarStatus { id:status; config:test.config;x:bar.x+bar.width-width-4;y:bar.y;width:contentLength;height:bar.height }
        Text { x:70;y:250;text:'Left and Right — 32 px rails, square app targets, no nested status pills';color:'white' }
        Dock { id:left; x:20;y:250;component:'hyprbar';outputName:'eDP-1';config:test.edge('left');service:service;maximumLength:620;
            width:implicitWidth;height:implicitHeight;trailingLength:leftStatus.contentLength+8 }
        TaskbarStatus { id:leftStatus;edge:'left';config:test.config;x:left.x;y:left.y+left.height-height-4;width:left.width;height:contentLength }
        Dock { id:right; x:1048;y:250;component:'hyprbar';outputName:'eDP-1';config:test.edge('right');service:service;maximumLength:620;
            width:implicitWidth;height:implicitHeight;trailingLength:rightStatus.contentLength+8 }
        TaskbarStatus { id:rightStatus;edge:'right';config:test.config;x:right.x;y:right.y+right.height-height-4;width:right.width;height:contentLength }
    }
    function check(value,message) { if(!value) throw new Error(message); }
    function find(item,name) {
        if(item.objectName===name) return item;
        for(let child of item.children || []) { let result=find(child,name); if(result) return result; }
        return null;
    }
    Timer { interval:500;running:true;onTriggered: {
        try {
            test.check(left.width===32 && right.width===32,'side rails ignore obsolete title widths');
            let button=test.find(left,'dockItem1');
            test.check(button.width===28 && button.height===28,'square side app target');
            test.check(!test.find(button,'dockLauncherLogo').visible,'app icons retain their identity');
            test.check(dock.height===32 && bar.height===32,'match Hyprpane thickness');
            let surface=test.find(dock,'dockBackground');
            test.check(surface.settings.vibrantColor===pane.sharedStyle('launcher').vibrantColor,'same center pill palette');
            test.check(surface.settings.radius===pane.sharedStyle('launcher').radius,'same center pill shape');
            for(let rail of [status,leftStatus,rightStatus]) {
                test.check(rail.sharedPills.length===0,'no status group backdrops');
                test.check(!test.find(rail.moduleItems.audio,'pillBackground').visible,'no individual status pill');
            }
            window.contentItem.grabToImage(result=> {
                result.saveToFile('/tmp/hypr-panels-style.png');
                console.log('PANEL_STYLE_OK'); Qt.quit();
            });
        } catch(error) { console.error('PANEL_STYLE_FAILED '+error); Qt.exit(1); }
    }}
    Timer { interval:5000;running:true;onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', PAYLOAD.as_uri())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            data = json.loads((ROOT / 'config/hyprshell/settings.json').read_text())
            for name in ('hyprbar', 'hyprdock'):
                data['panels'][name].update(thickness=32, iconSize=24, spacing=3, background='inherit')
            target = root / 'config/hyprshell/settings.json'
            target.parent.mkdir(parents=True)
            target.write_text(json.dumps(data))
            fixture = root / 'Check.qml'
            fixture.write_text(source)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('PANEL_STYLE_OK', output)
            self.assertNotIn('TypeError', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('Binding loop', output)
