"""Network commands and the native page, isolated from this laptop's networks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import network

WIFI = '11111111-1111-1111-1111-111111111111'
VPN = '22222222-2222-2222-2222-222222222222'


class NetworkTests(unittest.TestCase):
    def snapshot(self, ident=VPN, active=False):
        return {'name': 'Office', 'uuid': ident, 'type': 'vpn', 'active': active, 'revision': 'current'}

    def test_escaped_duplicate_names_and_active_sort(self):
        with patch.object(network, 'nmcli', side_effect=[f'Office\\:West\\\\desk:{VPN}:vpn\nOffice:{WIFI}:802-11-wireless\n', WIFI + '\n']):
            rows = network.profiles()
        self.assertEqual(rows[0]['uuid'], WIFI)
        self.assertTrue(rows[0]['active'])
        self.assertEqual(rows[1]['name'], 'Office:West\\desk')
        self.assertFalse(rows[1]['active'])
        self.assertNotEqual(rows[0]['revision'], rows[1]['revision'])
        with self.assertRaises(ValueError): network.fields('unfinished\\')
        with patch.object(network, 'nmcli', side_effect=['wrong:fields\n', '']):
            with self.assertRaises(ValueError): network.profiles()

    def test_status_reads_only_metadata_and_cached_connectivity(self):
        with patch.object(network, 'nmcli', side_effect=[f'Office:{VPN}:vpn\n', '', 'portal\n']) as command, patch.object(network.shutil, 'which', return_value='/usr/bin/nm-connection-editor'):
            result = network.request({'operation': 'status'})
        self.assertEqual(result['connectivity'], 'portal')
        self.assertTrue(result['editor'])
        self.assertNotIn('--show-secrets', repr(command.call_args_list))
        self.assertEqual(command.call_args_list[-1].args[0], ['--terse', 'networking', 'connectivity'])

    def test_invalid_stale_or_removed_connection_never_mutates(self):
        with patch.object(network, 'profiles', return_value=[self.snapshot()]), patch.object(network, 'nmcli') as command, patch.object(network, 'editor') as editor:
            for payload in ({'uuid': '$(bad)', 'expected': 'current'}, {'uuid': WIFI, 'expected': 'current'}, {'uuid': VPN, 'expected': 'stale'}):
                with self.assertRaises(ValueError): network.request({'operation': 'forget', 'confirmed': True, **payload})
            command.assert_not_called(); editor.assert_not_called()

    def test_connect_authenticates_in_detached_terminal_by_uuid(self):
        with patch.object(network, 'profiles', return_value=[self.snapshot()]), patch.object(network.shutil, 'which', return_value='/usr/bin/kitty'), patch.object(network.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            result = network.request({'operation': 'connect', 'uuid': VPN, 'expected': 'current'})
        args = run.call_args.args[0]
        self.assertEqual(args[-8:], ['nmcli', '--ask', '--wait', '60', 'connection', 'up', 'uuid', VPN])
        self.assertIn('--detach', args); self.assertIn('--hold', args)
        self.assertNotIn('shell', run.call_args.kwargs)
        self.assertNotIn('profiles', result)
        self.assertIn('authentication', result['message'])

    def test_forget_requires_confirmation_and_inactive_connection(self):
        payload = {'operation': 'forget', 'uuid': VPN, 'expected': 'current'}
        with patch.object(network, 'profiles', return_value=[self.snapshot()]), patch.object(network, 'nmcli') as command, patch.object(network, 'status', return_value={'ok': True}):
            with self.assertRaises(ValueError): network.request(payload)
            command.assert_not_called()
            network.request({**payload, 'confirmed': True})
            command.assert_called_once_with(['connection', 'delete', 'uuid', VPN])
        with patch.object(network, 'profiles', return_value=[self.snapshot(active=True)]), patch.object(network, 'nmcli') as command:
            with self.assertRaises(ValueError): network.request({**payload, 'confirmed': True})
            command.assert_not_called()

    def test_hidden_wifi_preserves_ssid_and_keeps_password_in_terminal(self):
        ssid = ' Café: $(not a shell) '
        with patch.object(network, 'connect_terminal', return_value={'ok': True}) as launch:
            self.assertTrue(network.request({'operation': 'hidden', 'ssid': ssid})['ok'])
            launch.assert_called_once_with(['device', 'wifi', 'connect', ssid, 'hidden', 'yes'])
            for invalid in ('', 'a' * 33, '界' * 11, 'two\nlines', 'nul\0byte', None):
                with self.assertRaises(ValueError): network.request({'operation': 'hidden', 'ssid': invalid})
            self.assertEqual(launch.call_count, 1)

    def test_disconnect_checks_active_and_keeps_completed_result_if_refresh_fails(self):
        payload = {'operation': 'disconnect', 'uuid': VPN, 'expected': 'current'}
        with patch.object(network, 'profiles', return_value=[self.snapshot()]), patch.object(network, 'nmcli') as command:
            with self.assertRaises(ValueError): network.request(payload)
            command.assert_not_called()
        with patch.object(network, 'profiles', return_value=[self.snapshot(active=True)]), patch.object(network, 'nmcli') as command, patch.object(network, 'status', side_effect=ValueError('failed')):
            result = network.request(payload)
            command.assert_called_once_with(['connection', 'down', 'uuid', VPN])
            self.assertTrue(result['ok']); self.assertIn('Refresh', result['message'])

    def test_editor_whitelist_and_uuid_arguments(self):
        with patch.object(network, 'editor') as editor:
            for kind in ('802-11-wireless', '802-3-ethernet', 'vpn', 'wireguard'):
                network.request({'operation': 'create', 'type': kind})
                self.assertEqual(editor.call_args.args[0], ['--create', '--type=' + kind])
            with self.assertRaises(ValueError): network.request({'operation': 'create', 'type': '--bad'})
            with patch.object(network, 'profiles', return_value=[self.snapshot()]):
                network.request({'operation': 'edit', 'uuid': VPN, 'expected': 'current'})
                editor.assert_called_with(['--edit=' + VPN])
        with patch.object(network.shutil, 'which', return_value='/usr/bin/nm-connection-editor'), patch.object(network.subprocess, 'Popen') as launch:
            network.editor(['--create', '--type=vpn'])
            self.assertTrue(launch.call_args.kwargs['start_new_session'])
            self.assertEqual(launch.call_args.kwargs['stdin'], subprocess.DEVNULL)
        with patch.object(network.shutil, 'which', return_value=None):
            with self.assertRaises(ValueError): network.editor([])

    def test_service_permission_timeout_and_command_errors_are_actionable(self):
        for error, text in [('Could not create NMClient object: Could not connect', 'Cannot reach'), ('Operation not permitted', 'access was denied'), ('Not authorized', 'access was denied'), ('unknown failure', 'operation failed')]:
            with patch.object(network.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', error)):
                with self.assertRaisesRegex(ValueError, text): network.nmcli(['connection', 'show'])
        with patch.object(network.subprocess, 'run', side_effect=subprocess.TimeoutExpired('nmcli', 20)):
            with self.assertRaisesRegex(ValueError, 'in time'): network.nmcli([])
        with patch.object(network.subprocess, 'run', side_effect=FileNotFoundError):
            with self.assertRaisesRegex(ValueError, 'missing'): network.nmcli([])


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class NetworkNativeTests(unittest.TestCase):
    def test_lazy_page_search_forget_confirmation_failures_and_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            commands = root / 'bin'; commands.mkdir()
            fake = commands / 'nmcli'
            fake.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
state = Path(os.environ['NETWORK_TEST_STATE'])
args = sys.argv[1:]
with (state / 'calls').open('a') as log: log.write(json.dumps(args) + '\\n')
if (state / 'deny').exists():
    print('Operation not permitted', file=sys.stderr); sys.exit(1)
if args[-2:] == ['networking', 'connectivity']: print('full')
elif args[-1] == '--active': print({WIFI!r})
elif args[-2:] == ['connection', 'show']:
    print('Office:{WIFI}:802-11-wireless')
    if not (state / 'deleted').exists(): print('Office:{VPN}:vpn')
elif 'delete' in args:
    assert args[-1] == {VPN!r}
    (state / 'deleted').touch()
else: sys.exit(3)
''')
            fake.chmod(0o755)
            editor = commands / 'nm-connection-editor'; editor.write_text('#!/bin/sh\nexit 0\n'); editor.chmod(0o755)
            fixture = payload / 'NetworkNative.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: test
    property int phase: 0
    property bool checkedWidth: false
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    Process { id: denial; command: ["touch", "DENY_PATH"] }
    Process { id: recovery; command: ["python3", "-c", "from pathlib import Path; Path('DENY_PATH').unlink()"] }
    function find(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let match = find(child, name); if (match) return match; }
        return null;
    }
    function fail(message) { console.error("NETWORK_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 80; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded) return;
            let window = controller.window;
            if (test.phase === 0) { controller.open(); test.phase = 1; return; }
            if (!window) { if (test.phase === 10) { console.log("NETWORK_NATIVE_OK"); Qt.quit(); } return; }
            let loader = find(window.contentItem, "settingsNetworkLoader");
            let page = loader ? loader.item : null;
            if (test.phase === 1) {
                if (page) { test.fail("loaded before navigation"); return; }
                window.searchQuery = "enterprise";
                if (window.searchResults.length !== 1 || window.searchResults[0].section !== -15) { test.fail("search"); return; }
                window.section = -15; test.phase = 2;
            } else if (test.phase === 2 && page && page.loaded && !page.busy) {
                if (!test.checkedWidth) { window.contentItem.Window.window.width = 720; test.phase = 11; return; }
                if (page.profiles.length !== 2 || page.connectivity !== "full") { test.fail("initial status"); return; }
                if (find(page, "forgetNetwork-WIFI_UUID").enabled) { test.fail("active forget allowed"); return; }
                find(page, "networkSearch").text = "vpn";
                if (page.filtered.length !== 1) { test.fail("filter"); return; }
                find(page, "forgetNetwork-VPN_UUID").clicked();
                if (!page.pendingForget || page.busy) { test.fail("missing confirmation"); return; }
                find(page, "cancelForgetNetwork").clicked();
                if (page.pendingForget) { test.fail("cancel"); return; }
                find(page, "forgetNetwork-VPN_UUID").clicked();
                find(page, "confirmForgetNetwork").clicked(); test.phase = 3;
            } else if (test.phase === 11) {
                if (page.width < 1 || page.width > loader.width + 1) { test.fail("page width"); return; }
                for (let child of page.children) {
                    if (child.visible && (child.x < -1 || child.x + child.width > page.width + 1)) { test.fail("horizontal overflow"); return; }
                }
                test.checkedWidth = true; window.contentItem.Window.window.width = 1180; test.phase = 2;
            } else if (test.phase === 3 && page && !page.busy && page.profiles.length === 1) {
                if (!page.success || page.pendingForget) { test.fail("delete result"); return; }
                window.section = -2; test.phase = 4;
            } else if (test.phase === 4) {
                if (page) { test.fail("page retained after navigation"); return; }
                denial.running = true; test.phase = 5;
            } else if (test.phase === 5 && !denial.running) {
                window.section = -15; test.phase = 6;
            } else if (test.phase === 6 && page && !page.busy && !page.success) {
                if (!page.message.includes("access was denied")) { test.fail("missing service error"); return; }
                if (window.dirty || window.saving) { test.fail("saved unrelated preferences"); return; }
                recovery.running = true; test.phase = 7;
            } else if (test.phase === 7 && !recovery.running) {
                find(page, "refreshNetwork").clicked(); test.phase = 8;
            } else if (test.phase === 8 && page && !page.busy && page.success) {
                if (page.profiles.length !== 1 || !page.loaded) { test.fail("error recovery"); return; }
                find(page, "refreshNetwork").clicked();
                window.visible = false; test.phase = 10;
                if (!controller.loaded || !loader.item) { test.fail("unloaded during command"); return; }
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.fail("timeout") }
}
'''.replace('WIFI_UUID', WIFI).replace('VPN_UUID', VPN).replace('DENY_PATH', str(root / 'deny')))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', PATH=str(commands) + os.pathsep + os.environ['PATH'], NETWORK_TEST_STATE=str(root))
            result = subprocess.run(['quickshell', '-p', str(fixture)], capture_output=True, text=True, env=env, timeout=15)
            output = result.stdout + result.stderr
            self.assertIn('NETWORK_NATIVE_OK', output, output)
            for error in ('NETWORK_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            deletes = [args for args in calls if 'delete' in args]
            self.assertEqual(len(deletes), 1)
            self.assertEqual(deletes[0][-1], VPN)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())


if __name__ == '__main__':
    unittest.main()
