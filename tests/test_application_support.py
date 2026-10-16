"""Narrow application edits reuse settings locking, backups and stale-draft checks."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'config/quickshell'
spec = importlib.util.spec_from_file_location('app_backend', PAYLOAD / 'settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class ApplicationPreferencesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'),
                              XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        self.env.start()
        self.addCleanup(self.env.stop)
        self.target = self.root / 'config/hyprshell/settings.json'
        self.data = copy.deepcopy(backend.DEFAULTS)
        self.data['bar']['clockFormat'] = 'hh:mm'
        backend.save(self.data)

    def action(self, **action):
        backend.save(backend.DEFAULTS, app_action=action)
        return json.loads(self.target.read_text())

    def test_pin_order_modes_uninstall_and_restart(self):
        self.action(action='pin', component='hyprdock', id='kitty.desktop')
        self.action(action='pin', component='hyprbar', id='My App.desktop')
        data = self.action(action='pin', component='hyprdock', id='missing.desktop')
        self.assertEqual(data['pins']['shared'], ['kitty.desktop', 'My App.desktop', 'missing.desktop'])
        data = self.action(action='reorder', component='hyprdock', id='missing.desktop', index=0)
        self.assertEqual(data['pins']['shared'], ['missing.desktop', 'kitty.desktop', 'My App.desktop'])
        self.action(action='mode', mode='separate')
        self.action(action='pin', component='hyprdock', id='org.example.Dock.desktop')
        data = self.action(action='pin', component='hyprbar', id='org.example.Bar.desktop')
        self.assertEqual(data['pins']['hyprdock'], ['org.example.Dock.desktop'])
        self.assertEqual(data['pins']['hyprbar'], ['org.example.Bar.desktop'])
        data = self.action(action='mode', mode='shared')
        data = self.action(action='unpin', component='hyprbar', id='kitty.desktop')
        self.assertEqual(data['pins']['shared'], ['missing.desktop', 'My App.desktop'])
        self.assertEqual(backend.validate(json.loads(self.target.read_text())), data)
        self.assertEqual(data['bar'], self.data['bar'])
        self.assertEqual(data['items'], self.data['items'])

    def test_matching_validation_and_rollback(self):
        data = self.action(action='match', key='DifferentWindowClass', id='org.example.App.desktop')
        self.assertEqual(data['pins']['matches'], {'DifferentWindowClass': 'org.example.App.desktop'})
        data = self.action(action='match', key='DifferentWindowClass', id=None)
        self.assertEqual(data['pins']['matches'], {})
        before = self.target.read_bytes()
        backups = set((self.root / 'state').rglob('*'))
        for action in [dict(action='pin', component='hyprpane', id='app.desktop'),
                       dict(action='pin', component='hyprdock', id='/tmp/app.desktop'),
                       dict(action='match', key='bad\nclass', id='app.desktop'),
                       dict(action='match', key='class', id='app.desktop\n'),
                       dict(action='reorder', component='hyprbar', id='absent.desktop', index=0),
                       dict(action='mode', mode='bad')]:
            with self.subTest(action=action), self.assertRaises(ValueError):
                backend.save(backend.DEFAULTS, app_action=action)
            self.assertEqual(self.target.read_bytes(), before)
            self.assertEqual(set((self.root / 'state').rglob('*')), backups)

    def test_other_settings_survive_and_stale_settings_draft_is_rejected(self):
        old = json.loads(self.target.read_text())
        self.action(action='pin', component='hyprdock', id='kitty.desktop')
        with self.assertRaisesRegex(ValueError, 'changed outside'):
            backend.save(old, expected=old)
        latest = json.loads(self.target.read_text())
        latest['bar']['clockFormat'] = 'hh:mm:ss'
        backend.save(latest)
        after = self.action(action='match', key='custom-class', id='kitty.desktop')
        self.assertEqual(after['bar']['clockFormat'], 'hh:mm:ss')
        self.assertEqual(after['pins']['shared'], ['kitty.desktop'])

    def test_discoverable_desktop_filenames_are_not_shell_commands(self):
        for app in ['My App.desktop', 'Ứng dụng.desktop', 'app+name.desktop']:
            self.action(action='pin', component='hyprdock', id=app)
        for app in ['.desktop', ' app.desktop', '../app.desktop', 'sub/app.desktop', 'bad\0.desktop']:
            self.assertFalse(backend.desktop_id(app))


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class ApplicationNativeTests(unittest.TestCase):
    def test_native_preferences_writer_reloads_pins_and_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            source = '''import QtQuick
import Quickshell
import "PAYLOAD"
ShellRoot {
    id: test
    property int step: 0
    SettingsStore { id: preferences }
    ApplicationService { id: service; store: preferences; entries: []; windows: [] }
    Timer { interval:80; running:true; repeat:true; onTriggered: {
        if (!preferences.loaded || service.busy) return;
        if (service.error) { console.error('APP_WRITER_FAILED '+service.error); Qt.exit(1); return; }
        let pins=preferences.config.pins;
        if (test.step===0) {
            service.edit({action:'pin',component:'hyprdock',id:'missing.desktop'}); test.step=1;
        } else if(test.step===1 && pins.shared.indexOf('missing.desktop')>=0) {
            service.edit({action:'match',key:'CustomClass',id:'missing.desktop'}); test.step=2;
        } else if(test.step===2 && pins.matches.CustomClass==='missing.desktop') {
            service.edit({action:'unpin',component:'hyprbar',id:'missing.desktop'}); test.step=3;
        } else if(test.step===3 && pins.shared.length===0) {
            console.log('APP_WRITER_OK'); Qt.quit();
        }
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', PAYLOAD.as_uri())
            (root / 'Check.qml').write_text(source)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Check.qml')],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('APP_WRITER_OK', output)
            saved = json.loads((root / 'config/hyprshell/settings.json').read_text())
            self.assertEqual(saved['pins']['shared'], [])
            self.assertEqual(saved['pins']['matches'], {'CustomClass': 'missing.desktop'})

    def test_service_and_manager_react_to_window_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            source = '''import QtQuick
import Quickshell
import "PAYLOAD"
ShellRoot {
    id: test
    QtObject {
        id: store
        property var config: ({pins:{mode:'shared',shared:['missing.desktop','kitty.desktop'],hyprdock:[],hyprbar:[],matches:{}}})
        function reload() {}
    }
    QtObject {
        id: application
        property string id: 'kitty'
        property string name: 'Kitty'
        property string icon: 'kitty'
        property string startupClass: 'kitty'
    }
    QtObject { id: workspaceObject; property int id: 2; property string name: '2' }
    QtObject { id: monitorObject; property string name: 'HDMI-A-1' }
    QtObject { id: waylandObject; property string appId: 'kitty' }
    QtObject {
        id: client
        property string address: 'cd'
        property string title: 'Second'
        property bool activated: false
        property bool urgent: false
        property var workspace: workspaceObject
        property var monitor: monitorObject
        property var wayland: waylandObject
        property var lastIpcObject: ({class:'kitty'})
    }
    ApplicationService {
        id: service
        store: store
        entries: [application]
        windows: [{address:'ab',title:'First',activated:true,workspace:{id:1,name:'1'},monitor:{name:'eDP-1'},lastIpcObject:{class:'kitty'}},
                  client]
    }
    Window { visible:true; width:300; height:900
        ApplicationManager { id: manager; width:264; service:service }
    }
    function check(value,message) { if(!value) throw new Error(message); }
    property int step: 0
    Timer { interval:100; running:true; repeat:true; onTriggered: {
        try {
            if (test.step===0) {
                let groups=service.groups('hyprdock');
                test.check(groups.length===2 && groups[1].windows.length===2,'group windows and missing pin');
                test.check(groups[1].active && !groups[0].installed,'focus and missing metadata');
                test.check(groups[1].entry===application,'native launch entry preserved');
                manager.selectedAddress='cd';
                test.check(manager.selected.title==='Second','window selection');
                application.name='Renamed terminal';
                application.startupClass='CustomTerminal';
                waylandObject.appId='CustomTerminal';
                client.lastIpcObject={class:'CustomTerminal'};
            } else if (test.step===1) {
                test.check(service.groups('hyprdock')[1].name==='Renamed terminal','metadata refresh');
                test.check(service.windowRows[1].appId==='kitty.desktop','matching metadata refresh');
                client.title='Changed'; client.activated=true; client.urgent=true;
                workspaceObject.id=3; workspaceObject.name='three'; monitorObject.name='eDP-1';
            } else if (test.step===2) {
                test.check(manager.selected.title==='Changed' && manager.selected.workspace===3,'native title/workspace changes');
                test.check(manager.selected.workspaceName==='three' && manager.selected.output==='eDP-1','native workspace name/output changes');
                test.check(manager.selected.active && manager.selected.urgent,'native focus/urgency changes');
                store.config={pins:{mode:'shared',shared:['missing.desktop','kitty.desktop'],hyprdock:[],hyprbar:[],matches:{CustomTerminal:'missing.desktop'}}};
            } else if (test.step===3) {
                test.check(service.windowRows[1].appId==='missing.desktop','identity correction refresh');
                service.windows=[{address:'cd',title:'Replacement',activated:true,workspace:{id:4,name:'four'},monitor:{name:'eDP-1'},lastIpcObject:{class:'kitty'}}];
            } else if (test.step===4) {
                test.check(manager.selected.title==='Replacement' && manager.selected.workspace===4,'window model replacement');
                service.windows=[];
            } else {
                test.check(manager.selected===null && service.groups('hyprdock')[1].windows.length===0,'closed window disappears');
                test.check(!service.windowAction('close','cd'),'stale actions rejected');
                test.check(!service.launch('missing.desktop'),'missing app fails safely');
                let launcher=Qt.createComponent('PAYLOAD/LauncherMenu.qml');
                test.check(launcher.status===Component.Ready,launcher.errorString());
                console.log('APPLICATION_SUPPORT_OK'); Qt.quit();
            }
            test.step++;
        } catch(error) { console.error('APPLICATION_SUPPORT_FAILED '+error); Qt.exit(1); }
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', PAYLOAD.as_uri())
            (root / 'Check.qml').write_text(source)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Check.qml')],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('APPLICATION_SUPPORT_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'APPLICATION_SUPPORT_FAILED'):
                self.assertNotIn(error, output)
