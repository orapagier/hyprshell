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
import firewall


class FirewallTests(unittest.TestCase):
    def snapshot(self):
        return {'details': 'public', 'services': ['ssh'], 'ports': ['8080/tcp'], 'rich': ['rule family="ipv4" source address="192.0.2.1" drop'], 'revision': 'current'}

    def fake(self, args):
        return 'ssh http' if '--get-services' in args else ''

    def test_confirmation_and_stale_revision_prevent_mutation(self):
        with patch.object(firewall, 'context', return_value=('public', 'runtime', ['public'])), patch.object(firewall, 'snapshot', return_value=self.snapshot()), patch.object(firewall, 'command') as command:
            for fields in ({}, {'confirmed': True, 'expected': 'old'}):
                with self.assertRaises(ValueError): firewall.request({'operation': 'add-port', 'value': '8080/tcp', **fields})
            command.assert_not_called()

    def test_invalid_inputs_never_mutate(self):
        with patch.object(firewall, 'context', return_value=('public', 'runtime', ['public'])), patch.object(firewall, 'snapshot', return_value=self.snapshot()), patch.object(firewall, 'command', side_effect=self.fake) as command:
            for operation, value in [('add-service', '--panic-on'), ('add-service', 'unknown'), ('add-port', '0/tcp'), ('add-port', '65536/tcp'), ('add-port', '90-80/udp'), ('add-port', '80/tcp;bad'), ('block-source', '$(bad)'), ('block-source', None), ('remove-rich', '--bad')]:
                with self.assertRaises(ValueError): firewall.request({'operation': operation, 'value': value, 'confirmed': True, 'expected': 'current'})
            self.assertTrue(all(call.args[0] == ['--get-services'] for call in command.call_args_list))

    def test_scope_and_source_are_exact_arguments_without_reload(self):
        for scope in ('runtime', 'permanent'):
            with patch.object(firewall, 'context', return_value=('public', scope, ['public'])), patch.object(firewall, 'snapshot', return_value=self.snapshot()), patch.object(firewall, 'command', side_effect=self.fake) as command:
                result = firewall.request({'operation': 'block-source', 'value': '2001:db8::1', 'confirmed': True, 'expected': 'current'})
                args = command.call_args_list[0].args[0]
                self.assertEqual(args, ['--zone=public', *(['--permanent'] if scope == 'permanent' else []), '--add-rich-rule=rule family="ipv6" priority="-100" source address="2001:db8::1/128" drop'])
                self.assertTrue(result['ok'])
                self.assertNotIn('--reload', repr(command.call_args_list))

    def test_completed_change_survives_refresh_failure(self):
        with patch.object(firewall, 'context', side_effect=[('public', 'runtime', ['public']), ValueError('unavailable')]), patch.object(firewall, 'snapshot', return_value=self.snapshot()), patch.object(firewall, 'command'):
            result = firewall.request({'operation': 'remove-port', 'value': '8080/tcp', 'confirmed': True, 'expected': 'current'})
            self.assertTrue(result['ok']); self.assertIn('Refresh', result['message'])

    def test_errors_and_no_shell(self):
        for error, expected in [('DBUS_ERROR: Operation not permitted', 'Cannot access'), ('Authorization failed', 'Cannot access'), ('FirewallD is not running', 'stopped')]:
            with patch.object(firewall.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', error)):
                with self.assertRaisesRegex(ValueError, expected): firewall.command(['--state'])
        with patch.object(firewall.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'public', '')) as run:
            firewall.command(['--get-default-zone'])
            self.assertNotIn('shell', run.call_args.kwargs)
            self.assertEqual(run.call_args.kwargs['timeout'], 30)

    def test_enable_requires_confirmation_and_only_launches_terminal(self):
        with patch.object(firewall.subprocess, 'run') as run:
            with self.assertRaises(ValueError): firewall.request({'operation': 'enable'})
            run.assert_not_called()
        with patch.object(firewall.shutil, 'which', return_value='/usr/bin/kitty'), patch.object(firewall.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            firewall.request({'operation': 'enable', 'confirmed': True})
            self.assertEqual(run.call_args.args[0][-5:], ['sudo', 'systemctl', 'enable', '--now', 'firewalld.service'])

    def test_context_rejects_invented_zone_and_scope(self):
        with patch.object(firewall, 'command', return_value='public home'):
            for payload in ({'scope': 'both'}, {'zone': '--bad'}, {'zone': 'trusted'}):
                with self.assertRaises(ValueError): firewall.context(payload)


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class NativeTests(unittest.TestCase):
    def test_page_navigation_confirmation_drafts_and_access_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            qml = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', qml, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            commands = root / 'bin'; commands.mkdir()
            fake = commands / 'firewall-cmd'
            fake.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
root = Path(os.environ['FIREWALL_TEST_ROOT'])
args = sys.argv[1:]
with (root / 'calls').open('a') as log: log.write(json.dumps(args) + '\\n')
if (root / 'deny').exists(): print('DBUS_ERROR: Operation not permitted', file=sys.stderr); sys.exit(36)
if '--get-zones' in args: print('public home')
elif '--get-default-zone' in args: print('public')
elif '--get-active-zones' in args: print('public\\n  interfaces: wlan0')
elif '--get-services' in args: print('ssh http')
elif '--list-all' in args: print('public\\n  services: ssh')
elif '--list-services' in args: print('ssh')
elif '--list-ports' in args: print('8080/tcp')
elif '--list-rich-rules' in args: print('rule family="ipv4" source address="192.0.2.1" drop')
elif '--add-service=http' in args: print('success')
else: sys.exit(2)
''')
            fake.chmod(0o755)
            fixture = qml / 'FirewallNative.qml'
            fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    Process { id: deny; command: ["touch", "DENY_PATH"] }
    function find(root, name) { if (!root) return null; if (root.objectName === name) return root; for (let child of root.children || []) { let match = find(child, name); if (match) return match; } return null; }
    function fail(message) { console.error("FIREWALL_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 80; running: true; repeat: true; onTriggered: {
        if (!prefs.loaded) return;
        if (test.phase === 0) { controller.open(); test.phase = 1; return; }
        let window = controller.window;
        if (!window) return;
        let loader = find(window.contentItem, "settingsFirewallLoader"); let page = loader ? loader.item : null;
        if (test.phase === 1) {
            if (page) { test.fail("eager page"); return; }
            window.searchQuery = "firewall";
            if (window.searchResults.length !== 1 || window.searchResults[0].section !== -22) { test.fail("search"); return; }
            window.section = -22; test.phase = 2;
        } else if (test.phase === 2 && page && page.loaded && !page.busy) {
            find(page, "firewallService").text = "http";
            find(page, "addFirewallService").clicked();
            if (!page.pending || page.busy) { test.fail("confirmation"); return; }
            window.section = -2; test.phase = 3;
        } else if (test.phase === 3) {
            if (!page || !page.dirty || !window.manualDirty) { test.fail("draft not retained"); return; }
            window.section = -22; find(page, "confirmFirewall").clicked(); test.phase = 4;
        } else if (test.phase === 4 && page && !page.busy && !page.dirty) {
            if (!page.success || !page.message.includes("Current rule changed")) { test.fail("apply"); return; }
            window.section = -2; test.phase = 5;
        } else if (test.phase === 5) {
            if (page) { test.fail("clean page retained"); return; }
            deny.running = true; test.phase = 6;
        } else if (test.phase === 6 && !deny.running) { window.section = -22; test.phase = 7; }
        else if (test.phase === 7 && page && !page.busy && !page.success) {
            if (page.loaded || !page.message.includes("Cannot access")) { test.fail("access failure"); return; }
            if (window.dirty || window.saving) { test.fail("unrelated settings saved"); return; }
            console.warn("FIREWALL_NATIVE_OK"); Qt.quit();
        }
    } }
    Timer { interval: 15000; running: true; onTriggered: test.fail("timeout") }
}
'''.replace('DENY_PATH', str(root / 'deny')))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='', PATH=str(commands) + os.pathsep + os.environ['PATH'], FIREWALL_TEST_ROOT=str(root))
            result = subprocess.run(['quickshell', '-p', str(fixture)], env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr + '\nEXIT ' + str(result.returncode)
            self.assertIn('FIREWALL_NATIVE_OK', output, output)
            for error in ('FIREWALL_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            self.assertEqual(sum('--add-service=http' in row for row in calls), 1)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
