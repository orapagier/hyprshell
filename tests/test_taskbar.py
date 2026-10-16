"""Native shared-service taskbar lifecycle, filters, and orientation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'config/quickshell'


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class TaskbarNativeTests(unittest.TestCase):
    def test_lifecycle_filters_and_four_edges(self):
        source = '''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "PAYLOAD"
import "PAYLOAD/SettingsModel.js" as Settings
ShellRoot {
    id: test
    property int step:0
    property var config: ({})
    SettingsStore { id: preferences }
    ApplicationService {
        id: service
        store:preferences
        entries:[{id:'test',name:'Test',icon:''}]
        windows:[{address:'aa',title:'First',activated:true,workspace:{id:1,name:'1'},monitor:{name:'eDP-1'},lastIpcObject:{class:'test'}},
                 {address:'bb',title:'Second',activated:false,workspace:{id:2,name:'2'},monitor:{name:'HDMI-A-1'},lastIpcObject:{class:'test'}}]
    }
    Window {
        visible:true; width:600; height:400
        Dock { id:bar; component:'hyprbar'; service:service; config:test.config.panels ? test.config : preferences.config; outputName:'eDP-1'; workspace:1; maximumLength:500; trailingLength:status.contentLength+8; width:implicitWidth; height:implicitHeight }
        TaskbarStatus { id:status; config:bar.config; width:contentLength; height:bar.height; x:bar.width-width }
    }
    function check(value,message) { if(!value) throw new Error(message); }
    function update(values) { let next=Settings.copy(test.config.panels ? test.config : preferences.config); Object.assign(next.panels.hyprbar,values); test.config=next; }
    Timer { interval:100; repeat:true; running:true; onTriggered: {
        try {
            if(!preferences.loaded || !service.windowRows.length) return;
            if(test.step===0) {
                let next=Settings.copy(preferences.config); next.panels.hyprpane.enabled=false;
                next.panels.hyprbar.enabled=true; test.config=next;
                test.check(bar.groups[0].windows.length===1,'current output filter');
                test.check(status.contentLength>0 && status.orderedItems('right').indexOf('audio')>=0,'inherited right items');
                test.check(bar.applicationLength + status.width < bar.width,'separate app and status space');
                test.update({windowMonitorScope:'all'});
                test.check(bar.groups[0].windows.length===2,'all output grouping');
            } else if(test.step===1) {
                test.update({grouped:false}); test.check(bar.groups.length===2,'ungrouped tasks');
                service.windows=[Object.assign({},service.windows[1],{title:'Renamed',activated:true})];
            } else if(test.step===2) {
                test.check(bar.groups.length===1 && bar.groups[0].name==='Renamed' && bar.groups[0].active,'close/title/focus lifecycle');
                test.update({windowWorkspaceScope:'current'}); test.check(bar.groups.length===0,'workspace filter');
                test.update({windowWorkspaceScope:'all'});
            } else if(test.step<=6) {
                test.update({position:['top','bottom','left','right'][test.step-3]});
                test.check(bar.vertical === (test.step>=5),'surface orientation');
            } else {
                console.log('TASKBAR_NATIVE_OK'); Qt.quit();
            }
            test.step++;
        } catch(error) { console.error('TASKBAR_NATIVE_FAILED '+error); Qt.exit(1); }
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', PAYLOAD.as_uri())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            fixture = root / 'Check.qml'
            fixture.write_text(source)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('TASKBAR_NATIVE_OK', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('TypeError', output)
