import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path):
    import run_shell_workload as workload
    import install_workload_probes as installer


def state(page='', settled=True):
    return {'instance': 'test', 'supported': True, 'safe': True, 'otherUiOpen': False,
            'settingsOpen': page == 'settings', 'dock': {'section': page, 'expanded': bool(page),
            'pageReady': bool(page), 'surfaceVisible': True, 'settled': settled}}


class WorkloadDriverTests(unittest.TestCase):
    def test_wait_requires_loaded_and_settled_observations(self):
        rows = [state('launcher', False), state('launcher'), state('launcher'), state('launcher')]
        with patch.object(workload, 'frame_call', side_effect=rows) as call, patch.object(workload.time, 'sleep'):
            self.assertEqual(workload.wait_state('test', 'launcher')['dock']['section'], 'launcher')
        self.assertEqual(call.call_count, 4)

    def test_reload_or_pending_edits_abort(self):
        for row in [dict(state(), instance='new'), dict(state(), safe=False)]:
            with self.subTest(row=row), patch.object(workload, 'frame_call', return_value=row):
                with self.assertRaises(RuntimeError):
                    workload.wait_state('test', '')

    def test_timeout_is_not_treated_as_open(self):
        with patch.object(workload, 'frame_call', return_value=state()), \
                patch.object(workload.time, 'monotonic', side_effect=[0, 0, 20]), \
                patch.object(workload.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'Timed out'):
                workload.wait_state('test', 'launcher')

    def test_existing_frame_capture_is_not_finished(self):
        with patch.object(workload, 'frame_call', return_value={'ok': False}) as call:
            with self.assertRaisesRegex(RuntimeError, 'Another frame'):
                workload.transition('test', 'launcher', 60)
            call.assert_called_once_with('startWorkloadFrames', workload.TIMEOUT + 5, 60)

    def test_action_failure_stops_owned_observer(self):
        calls = []
        def ipc(method, *args):
            calls.append(method)
            return {'startWorkloadFrames': {'ok': True, 'instance': 'test', 'capture': 'x'},
                    'workloadOpen': {'ok': False, 'error': 'failed'},
                    'workloadState': state(), 'frameResults': {}}[method]
        with patch.object(workload, 'frame_call', side_effect=ipc):
            with self.assertRaisesRegex(RuntimeError, 'failed'):
                workload.transition('test', 'launcher', 60)
        self.assertEqual(calls[-1], 'frameResults')

    def test_installer_refuses_unrelated_live_edit(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            (config / 'shell.qml').write_text('unrelated change')
            with self.assertRaisesRegex(RuntimeError, 'other edits'):
                installer.validate(config)

    def test_busy_editor_waits_without_discarding_edits(self):
        rows = [dict(state('settings'), busy=True), state('settings'), state('settings'), state('settings')]
        with patch.object(workload, 'frame_call', side_effect=rows), patch.object(workload.time, 'sleep'):
            self.assertTrue(workload.wait_state('test', 'settings')['settingsOpen'])

    def test_installer_recovery_restores_files_while_replacement_is_stopped(self):
        tree = {'errors': [], 'processes': {}}
        with patch.object(installer, 'discover_pid', return_value=42), \
                patch.object(installer, 'process_sample', return_value={'start': 99}), \
                patch.object(installer, 'tree_sample', return_value=tree), \
                patch.object(installer, 'run') as run, \
                patch.object(installer, 'restart') as restart:
            installer.recover(Path('/fixture'), Path('/helper'), Path('/backup'))
            self.assertEqual(restart.call_args.args[1]['root']['pid'], 42)
            run.assert_not_called()
            restart.call_args.kwargs['before_start']()
            run.assert_called_once_with('python3', '/helper', 'restore', '/backup', '--apply')


class WorkloadControlTests(unittest.TestCase):
    def test_native_controls_preserve_dirty_settings_and_validate_pages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'Check.qml').write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    id: root
    function check(value, message) { if (!value) { console.error(message); Qt.exit(1); throw new Error(message); } }
    QtObject {
        id: dock
        property bool expanded: false
        property string section: ""
        function open(name, keyboard) { section = name; expanded = true; }
        function dismissWithEscape() { section = ""; expanded = false; }
        function workloadState() { return {section: section, expanded: expanded}; }
    }
    QtObject {
        id: editor
        property bool dirty: false
        property bool manualDirty: false
        property bool saving: false
        property bool idle: true
        property bool uiOpened: false
        function hideEditor() { uiOpened = false; }
    }
    QtObject {
        id: settings
        property var window: editor
        function open() { editor.uiOpened = true; dock.open('settings', true); }
    }
    WorkloadControl { id: control; supported: true; dock: dock; settings: settings }
    Timer { interval: 10; running: true; onTriggered: {
        root.check(control.snapshot().supported, 'probe unavailable');
        root.check(!control.openPage('lock').ok && !dock.expanded, 'unsupported action executed');
        root.check(control.openPage('launcher').ok && dock.section === 'launcher', 'launcher failed');
        root.check(!control.openPage('audio').ok && dock.section === 'launcher', 'open page replaced');
        root.check(control.closePage().ok && !dock.expanded, 'close failed');
        root.check(control.openPage('settings').ok && editor.uiOpened, 'settings did not open');
        editor.dirty = true;
        root.check(!control.closePage().ok && editor.uiOpened, 'dirty edits were closed');
        editor.dirty = false; editor.manualDirty = true;
        root.check(!control.closePage().ok && editor.uiOpened, 'manual edits were closed');
        editor.manualDirty = false;
        root.check(control.closePage().ok && !editor.uiOpened, 'clean settings did not close');
        control.otherUiOpen = true;
        root.check(!control.openPage('power').ok, 'other overlay ignored');
        control.otherUiOpen = false; control.supported = false;
        root.check(!control.openPage('launcher').ok, 'unsupported mode allowed');
        console.info('WORKLOAD_CONTROL_OK'); Qt.quit();
    }}
    Timer { interval: 3000; running: true; onTriggered: Qt.exit(2) }
}''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(root / 'Check.qml')], env=env,
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('WORKLOAD_CONTROL_OK', result.stdout + result.stderr)

    def test_native_dock_reports_loaded_content_and_restores_closed_state(self):
        import shutil
        with tempfile.TemporaryDirectory(prefix='workload-dock-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__'))
            source = (payload / 'Hyprdock.qml').read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            source = '\n'.join(line for line in source.splitlines() if not any(token in line for token in
                              ('anchors { top: true;', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            source = source.replace('visible: true\n    color:', 'visible: true\n    implicitWidth: 1200; implicitHeight: 900\n    color:', 1)
            (payload / 'Hyprdock.qml').write_text(source)
            entry = payload / 'Probe.qml'
            entry.write_text('''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int step: 0
    SettingsStore { id: store }
    DesktopServices { id: services }
    NotificationInbox { id: inbox; preferences: store.config.notifications }
    ApplicationService { id: apps; store: store }
    SettingsController { id: editor; store: store; dockEnabled: true; dockResolver: () => dock.prepareSettings(); audioServices: services; batteryInfo: services.batteryInfo }
    Hyprdock { id: dock; store: store; services: services; inbox: inbox; applicationService: apps; settingsController: editor; motionEnabled: false }
    WorkloadControl { id: control; supported: true; dock: dock; settings: editor }
    function check(ok, message) { if (!ok) throw new Error(message); }
    Timer { interval: 200; running: true; repeat: true; onTriggered: {
        try {
            if (!store.loaded || control.snapshot().busy) return;
            let state = dock.workloadState();
            if (root.step === 0) {
                root.check(!state.expanded && !state.pageReady, 'initial state');
                root.check(control.openPage('calendar').ok, 'open calendar');
            } else if (root.step === 1) {
                if (!state.pageReady || !state.settled) return;
                root.check(state.section === 'calendar' && state.surfaceVisible, 'calendar readiness');
                root.check(control.closePage().ok, 'close calendar');
            } else if (root.step === 2) {
                root.check(!state.expanded && !state.section, 'closed state');
                root.check(control.openPage('settings').ok, 'open settings');
            } else if (root.step === 3) {
                if (!state.pageReady || !state.settled) return;
                root.check(state.section === 'settings' && editor.window.uiOpened, 'settings readiness');
                root.check(control.closePage().ok, 'close clean editor');
            } else {
                root.check(!state.expanded && !editor.window.uiOpened, 'restored state');
                console.info('NATIVE_WORKLOAD_DOCK_OK'); Qt.quit();
            }
            root.step++;
        } catch (error) { console.error(error); Qt.exit(1); }
    }}
    Timer { interval: 8000; running: true; onTriggered: { console.error(JSON.stringify(control.snapshot())); Qt.exit(2); } }
}''')
            (root / 'runtime').mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('NATIVE_WORKLOAD_DOCK_OK', result.stdout + result.stderr)
