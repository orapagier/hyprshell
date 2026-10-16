"""Native dock composition with isolated preferences and a stub application launcher."""
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
class DockNativeTests(unittest.TestCase):
    def test_native_icons_grouping_launch_and_drag_transaction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            commands = root / 'bin'
            commands.mkdir()
            log = root / 'launch.jsonl'
            stub = commands / 'uwsm'
            stub.write_text('#!/usr/bin/python3\nimport json,sys\nwith open(' + repr(str(log)) + ',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
            stub.chmod(0o755)
            preferences = json.loads((PAYLOAD / 'settings/defaults.json').read_text())
            preferences['panels']['hyprdock']['enabled'] = True
            preferences['pins']['shared'] = ['kitty.desktop', 'org.gnome.Nautilus.desktop', 'missing.desktop']
            target = root / 'config/hyprshell/settings.json'
            target.parent.mkdir(parents=True)
            target.write_text(json.dumps(preferences))
            source = '''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "PAYLOAD"
ShellRoot {
    id: test
    property int step: 0
    SettingsStore { id: preferences }
    ApplicationService {
        id: service
        store: preferences
        entries: [{id:'kitty',name:'Kitty',icon:'kitty'}, {id:'org.gnome.Nautilus',name:'Files',icon:'org.gnome.Nautilus'}]
        windows: [{address:'ab',title:'Terminal one',activated:true,workspace:{id:1,name:'1'},monitor:{name:'eDP-1'},lastIpcObject:{class:'kitty'}},
            {address:'bc',title:'Terminal two',activated:false,workspace:{id:2,name:'2'},monitor:{name:'HDMI-A-1'},lastIpcObject:{class:'kitty'}}]
    }
    Window {
        id: window
        visible:true; width:720; height:540; color:'#172333'
        Dock {
            id: dock
            x:40; y:460; width:implicitWidth; height:implicitHeight
            service:service; config:preferences.config; maximumLength:640
        }
        DockActions { id: actions; x:40; y:30; width:280; service:service; group:service.groups('hyprdock').find(g=>g.id==='kitty.desktop') || null }
    }
    function check(value,message) { if(!value) throw new Error(message); }
    Timer { interval:150; running:true; repeat:true; onTriggered: {
        try {
            if(!preferences.loaded || service.busy) return;
            if(service.error) throw new Error(service.error);
            if(test.step===0) {
                let groups=service.groups('hyprdock');
                test.check(groups.length===3 && groups[0].windows.length===2,'grouped windows and pins');
                test.check(groups[0].active && !groups[2].installed,'active and missing metadata');
                test.check(dock.entries.length===4,'launcher and app items');
                test.check(actions.group.windows.length===2,'window picker data');
                test.check(service.iconSource('unavailable-icon')!==undefined,'native icon fallback');
                dock.activate(groups[1],dock);
                test.check(dock.reorder('org.gnome.Nautilus.desktop','kitty.desktop'),'drag transaction accepted');
                test.step=1;
            } else if(test.step===1 && preferences.config.pins.shared[0]==='org.gnome.Nautilus.desktop') {
                test.check(service.groups('hyprdock')[0].id==='org.gnome.Nautilus.desktop','saved order reflected in dock');
                test.check(service.groups('hyprdock')[1].windows.length===2,'grouping survives reorder');
                window.contentItem.grabToImage(result=> {
                    result.saveToFile('/tmp/hyprdock-native.png');
                    console.log('DOCK_NATIVE_OK'); Qt.quit();
                });
                test.step=2;
            }
        } catch(error) { console.error('DOCK_NATIVE_FAILED '+error); Qt.exit(1); }
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', PAYLOAD.as_uri())
            fixture = root / 'Check.qml'
            fixture.write_text(source)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DOCK_NATIVE_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'DOCK_NATIVE_FAILED'):
                self.assertNotIn(error, output)
            self.assertEqual(json.loads(target.read_text())['pins']['shared'],
                             ['org.gnome.Nautilus.desktop', 'kitty.desktop', 'missing.desktop'])
            self.assertEqual([json.loads(line) for line in log.read_text().splitlines()],
                             [['app', '-t', 'service', '--', 'org.gnome.Nautilus.desktop']])
