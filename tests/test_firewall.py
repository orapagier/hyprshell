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

    def test_switch_requires_confirmation_and_uses_polkit_for_on_and_off(self):
        for operation, action in [('enable', 'enable'), ('disable', 'disable')]:
            with patch.object(firewall.subprocess, 'run') as run:
                with self.assertRaises(ValueError): firewall.request({'operation': operation})
                run.assert_not_called()
            with patch.object(firewall.os, 'geteuid', return_value=1000), patch.object(firewall.shutil, 'which', return_value='/usr/bin/pkexec'), patch.object(firewall.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run, patch.object(firewall, 'context', side_effect=firewall.FirewallStopped('stopped')):
                firewall.request({'operation': operation, 'confirmed': True})
                self.assertEqual(run.call_args.args[0], ['pkexec', '/usr/bin/systemctl', action, '--now', 'firewalld.service'])

    def test_authenticated_job_does_not_request_authentication_again_for_switch(self):
        with patch.object(firewall.os, 'geteuid', return_value=0), patch.object(firewall.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run, patch.object(firewall, 'context', side_effect=firewall.FirewallStopped('stopped')):
            firewall.request({'operation': 'disable', 'confirmed': True})
            self.assertEqual(run.call_args.args[0], ['/usr/bin/systemctl', 'disable', '--now', 'firewalld.service'])

    def test_stopped_firewall_is_off_not_unknown(self):
        with patch.object(firewall, 'context', side_effect=firewall.FirewallStopped('stopped')):
            status = firewall.request({'operation': 'status'})
            self.assertTrue(status['ok']); self.assertFalse(status['running'])

    def test_edit_adds_replacement_before_removing_old_rule(self):
        current = {**self.snapshot(), 'saved': self.snapshot()}
        ident = next(row['id'] for row in firewall.rule_rows(current) if row['kind'] == 'port')
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=self.fake) as command:
            firewall.request({'operation': 'edit-rule', 'id': ident, 'kind': 'port', 'value': '9000/udp', 'confirmed': True, 'expected': 'current'})
            changes = [call.args[0][-1] for call in command.call_args_list if '--add-' in call.args[0][-1] or '--remove-' in call.args[0][-1]]
            self.assertEqual(changes, ['--add-port=9000/udp', '--remove-port=8080/tcp'] * 2)

    def test_edit_failure_undoes_completed_changes(self):
        current = {**self.snapshot(), 'saved': self.snapshot()}
        ident = next(row['id'] for row in firewall.rule_rows(current) if row['kind'] == 'port')
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=['', ValueError('denied'), '']) as command:
            with self.assertRaisesRegex(ValueError, 'completed changes were undone'):
                firewall.request({'operation': 'edit-rule', 'id': ident, 'kind': 'port', 'value': '9000/udp', 'confirmed': True, 'expected': 'current'})
            self.assertEqual(command.call_args_list[-1].args[0], ['--zone=public', '--permanent', '--remove-port=9000/udp'])

    def test_edit_preserves_an_existing_replacement_on_rollback(self):
        current = {**self.snapshot(), 'ports': ['8080/tcp', '9000/udp'], 'saved': {**self.snapshot(), 'ports': ['8080/tcp', '9000/udp']}}
        ident = next(row['id'] for row in firewall.rule_rows(current) if row['value'] == '8080/tcp')
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=['', ValueError('denied'), '']) as command:
            with self.assertRaisesRegex(ValueError, 'completed changes were undone'):
                firewall.request({'operation': 'edit-rule', 'id': ident, 'kind': 'port', 'value': '9000/udp', 'confirmed': True, 'expected': 'current'})
            self.assertNotIn('--remove-port=9000/udp', repr(command.call_args_list))
            self.assertEqual(command.call_args_list[-1].args[0][-1], '--add-port=8080/tcp')

    def test_complex_source_rules_are_not_misrepresented_as_simple_blocks(self):
        simple = 'rule family="ipv4" priority="-100" source address="192.0.2.1/32" drop'
        self.assertEqual(firewall.blocked_address(simple), '192.0.2.1/32')
        self.assertIsNone(firewall.blocked_address(simple.replace(' drop', ' service name="ssh" drop')))

    def test_invalid_edit_never_changes_old_rule(self):
        current = {**self.snapshot(), 'saved': self.snapshot()}
        ident = next(row['id'] for row in firewall.rule_rows(current) if row['kind'] == 'port')
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command') as command:
            with self.assertRaises(ValueError): firewall.request({'operation': 'edit-rule', 'id': ident, 'kind': 'port', 'value': 'bad', 'confirmed': True, 'expected': 'current'})
            command.assert_not_called()

    def test_combined_changes_touch_only_one_rule_in_each_view(self):
        current = {**self.snapshot(), 'saved': self.snapshot()}
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=self.fake) as command:
            result = firewall.request({'operation': 'add-port', 'value': '9000/udp', 'confirmed': True, 'expected': 'current'})
            mutations = [call.args[0] for call in command.call_args_list if '--add-port=9000/udp' in call.args[0]]
            self.assertEqual(mutations, [['--zone=public', '--permanent', '--add-port=9000/udp'], ['--zone=public', '--add-port=9000/udp']])
            self.assertTrue(result['ok'])
            self.assertNotIn('--reload', repr(command.call_args_list))
            self.assertNotIn('--runtime-to-permanent', repr(command.call_args_list))

    def test_partial_failure_reports_saved_change_without_claiming_success(self):
        current = {**self.snapshot(), 'saved': self.snapshot()}
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=['', ValueError('denied')]):
            with self.assertRaisesRegex(ValueError, 'saved for future restarts, but could not be applied now'):
                firewall.request({'operation': 'add-port', 'value': '9000/udp', 'confirmed': True, 'expected': 'current'})

    def test_remove_permission_present_in_only_one_view(self):
        current = {**self.snapshot(), 'saved': {**self.snapshot(), 'ports': []}}
        with patch.object(firewall, 'context', return_value=('public', 'both', ['public'])), patch.object(firewall, 'snapshot', return_value=current), patch.object(firewall, 'command', side_effect=self.fake) as command:
            firewall.request({'operation': 'remove-port', 'value': '8080/tcp', 'confirmed': True, 'expected': 'current'})
            mutations = [call.args[0] for call in command.call_args_list if '--remove-port=8080/tcp' in call.args[0]]
            self.assertEqual(mutations, [['--zone=public', '--remove-port=8080/tcp']])

    def test_saved_changes_affect_combined_revision(self):
        outputs = ['public', 'ssh', '', '', 'public', 'ssh', '', '']
        with patch.object(firewall, 'command', side_effect=outputs):
            first = firewall.snapshot('public', 'both')
        with patch.object(firewall, 'command', side_effect=outputs[:4] + ['public', 'ssh http', '', '']):
            second = firewall.snapshot('public', 'both')
        self.assertNotEqual(first['revision'], second['revision'])

    def test_single_active_zone_selected_instead_of_unrelated_default(self):
        with patch.object(firewall, 'command', side_effect=['public home', 'home (default)\n  interfaces: wlan0']) as command:
            self.assertEqual(firewall.context({'scope': 'both'}), ('home', 'both', ['public', 'home']))
            self.assertEqual(command.call_count, 2)

    def test_refresh_recovers_a_removed_or_annotated_selected_zone(self):
        with patch.object(firewall, 'command', side_effect=['public home', 'public home', 'public (default)\n  interfaces: wlan0']):
            self.assertEqual(firewall.context({'operation': 'status', 'scope': 'both', 'zone': 'public (default)'}), ('public', 'both', ['public', 'home']))

    def test_context_rejects_invented_zone_and_scope(self):
        with patch.object(firewall, 'command', return_value='public home'):
            for payload in ({'scope': 'invalid'}, {'zone': '--bad'}, {'zone': 'trusted'}):
                with self.assertRaises(ValueError): firewall.context(payload)


    def test_dns_modes_require_confirmation_and_survive_firewall_status_failure(self):
        with patch.object(firewall.website_blocks, 'dns_change') as change:
            for operation in ('setup-website-dns', 'restore-website-dns', 'configure-website-dns'):
                with self.assertRaises(ValueError): firewall.request({'operation': operation})
            change.assert_not_called()
            payload = {'operation': 'configure-website-dns', 'mode': 'family', 'confirmed': True, 'expectedWebsite': 'revision'}
            with patch.object(firewall, 'request_firewall', side_effect=ValueError('firewall unavailable')), patch.object(firewall.website_blocks, 'status', return_value={'websiteRevision': 'new', 'dnsMode': 'family', 'websites': []}):
                result = firewall.request(payload)
            change.assert_called_once_with('configure-website-dns', payload)
            self.assertTrue(result['ok'])
            self.assertEqual(result['dnsMode'], 'family')


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
if (root / 'off').exists(): print('FirewallD is not running', file=sys.stderr); sys.exit(252)
path = root / ('saved.json' if '--permanent' in args else 'current.json')
state = json.loads(path.read_text()) if path.exists() else {{'services': ['ssh'], 'ports': ['8080/tcp']}}
if '--get-zones' in args: print('public home')
elif '--get-default-zone' in args: print('public')
elif '--get-active-zones' in args: print('public (default)\\n  interfaces: wlan0')
elif '--get-services' in args: print('ssh http')
elif '--list-all' in args: print(json.dumps(state, sort_keys=True))
elif '--list-services' in args: print(' '.join(state['services']))
elif '--list-ports' in args: print(' '.join(state['ports']))
elif '--list-rich-rules' in args: print('')
else:
    option = args[-1]
    for kind, key in [('service', 'services'), ('port', 'ports')]:
        for action in ['add', 'remove']:
            prefix = '--' + action + '-' + kind + '='
            if option.startswith(prefix):
                value = option[len(prefix):]
                if action == 'add' and value not in state[key]: state[key].append(value)
                elif action == 'remove' and value in state[key]: state[key].remove(value)
                path.write_text(json.dumps(state)); print('success'); sys.exit(0)
    sys.exit(2)
''')
            fake.chmod(0o755)
            pkexec = commands / 'pkexec'
            pkexec.write_text(f'''#!{sys.executable}
import json, os, runpy, subprocess, sys
from pathlib import Path
root = Path(os.environ['FIREWALL_TEST_ROOT'])
assert sys.argv[1] == '/usr/bin/python3'
script, arguments = sys.argv[2], sys.argv[3:]
request = json.loads(arguments[1])
with (root / 'auth-jobs').open('a') as log: log.write(request['operation'] + '\\n')
if (root / 'cancel-auth').exists(): sys.exit(126)
sys.path.insert(0, str(Path(script).parent))
import website_blocks, website_dns
website_dns.status = lambda: {{'dnsFilterReady': (root / 'dns-ready').exists(), 'dnsFilterInstalled': (root / 'dns-ready').exists() or (root / 'dns-recovery').exists(), 'dnsFilterRevision': ('ready' if (root / 'dns-ready').exists() else 'notready') + ((root / 'dns-mode').read_text() if (root / 'dns-mode').exists() else ''), 'dnsMode': json.loads((root / 'dns-mode').read_text())['mode'] if (root / 'dns-mode').exists() else 'automatic', 'dnsServers': json.loads((root / 'dns-mode').read_text())['servers'] if (root / 'dns-mode').exists() else []}}
def setup(domains):
    if not (root / 'dns-failed-once').exists():
        (root / 'dns-failed-once').touch(); (root / 'dns-recovery').touch()
        raise ValueError('DNS setup and automatic restoration failed. Use Restore DNS setup.')
    (root / 'dns-ready').touch()
def restore():
    (root / 'dns-ready').unlink(missing_ok=True); (root / 'dns-recovery').unlink(missing_ok=True)
def configure(domains, mode, servers):
    mode, servers = website_dns.selection(mode, servers)
    (root / 'dns-mode').write_text(json.dumps({{'mode': mode, 'servers': servers}}))
website_dns.configure = configure
website_dns.setup = setup
website_dns.restore = restore
website_dns.apply = lambda domains: (root / 'dns-rules').write_text(json.dumps(domains))
website_blocks.HOSTS = root / 'hosts'
website_blocks.LOCK = root / 'website-lock'
if not website_blocks.HOSTS.exists(): website_blocks.HOSTS.write_text('127.0.0.1 localhost\\n::1 localhost\\n')
os.geteuid = lambda: 0
original_run = subprocess.run
def run(args, **kwargs):
    if args[0] == '/usr/bin/systemctl':
        if args[1] == 'disable': (root / 'off').touch()
        elif args[1] == 'enable': (root / 'off').unlink(missing_ok=True)
        else: raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, '', '')
    assert args[0] != 'pkexec', 'Nested authentication request'
    return original_run(args, **kwargs)
subprocess.run = run
sys.argv = [script, *arguments]
runpy.run_path(script, run_name='__main__')
''')
            pkexec.chmod(0o755)
            fixture = qml / 'FirewallNative.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    Process { id: deny; command: ["touch", "DENY_PATH"] }
    Process { id: cancellation; command: ["touch", "CANCEL_PATH"] }
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
            window.implicitWidth = 720;
            window.section = -22; test.phase = 2;
        } else if (test.phase === 2 && page && page.loaded && !page.busy) {
            if (page.zone !== "public" || !page.snapshot.running) { test.fail("default zone parsing"); return; }
            if (page.width < 1 || page.width > loader.width + 1) { test.fail("page width"); return; }
            for (let child of page.children) {
                if (child.visible && (child.x < -1 || child.x + child.width > page.width + 1)) { test.fail("horizontal overflow"); return; }
            }
            find(page, "addFirewallRule").clicked();
            find(page, "firewallPreset").currentIndex = 1;
            if (!page.editing || !page.dirty) { test.fail("editor"); return; }
            window.section = -2; test.phase = 3;
        } else if (test.phase === 3) {
            if (!page || !page.dirty || !window.manualDirty) { test.fail("draft not retained"); return; }
            window.section = -22; find(page, "saveFirewallRule").clicked(); test.phase = 4;
        } else if (test.phase === 4 && page && !page.busy && !page.dirty) {
            let row = page.rules.find(row => row.kind === "service" && row.value === "http");
            if (!page.success || !row) { test.fail("add"); return; }
            find(page, "editFirewall-" + row.id).clicked();
            find(page, "firewallRuleKind").currentIndex = 1;
            find(page, "firewallPort").text = "invalid";
            find(page, "saveFirewallRule").clicked(); test.phase = 12;
        } else if (test.phase === 12 && page && !page.busy && !page.success) {
            if (!page.editing || !find(page, "saveFirewallRule").enabled) { test.fail("validation recovery"); return; }
            find(page, "refreshFirewall").clicked(); test.phase = 13;
        } else if (test.phase === 13 && page && !page.busy && page.success) {
            if (!page.editing || find(page, "firewallPort").text !== "invalid") { test.fail("refresh lost draft"); return; }
            find(page, "firewallPort").text = "9090";
            find(page, "saveFirewallRule").clicked(); test.phase = 5;
        } else if (test.phase === 5 && page && !page.busy && !page.dirty) {
            let row = page.rules.find(row => row.value === "9090/tcp");
            if (!page.success || !row || page.rules.some(row => row.value === "http")) { test.fail("edit"); return; }
            find(page, "removeFirewall-" + row.id).clicked();
            if (!page.pending || page.busy) { test.fail("remove confirmation"); return; }
            find(page, "confirmFirewall").clicked(); test.phase = 6;
        } else if (test.phase === 6 && page && !page.busy && !page.dirty) {
            if (page.rules.some(row => row.value === "9090/tcp")) { test.fail("remove"); return; }
            find(page, "addFirewallRule").clicked();
            find(page, "firewallRuleKind").currentIndex = 3;
            find(page, "firewallWebsite").text = "https://www.example.com/page";
            if (!find(page, "firewallSubdomains").checked || find(page, "saveFirewallRule").enabled) { test.fail("subdomain default or setup gate"); return; }
            find(page, "setupWebsiteDns").clicked();
            find(page, "confirmFirewall").clicked(); test.phase = 21;
        } else if (test.phase === 21 && page && !page.busy && !page.success) {
            if (!page.editing || !page.snapshot.dnsFilterInstalled || !find(page, "repairWebsiteDns").visible || find(page, "setupWebsiteDns").visible) { test.fail("recovery unavailable after failure"); return; }
            let missingStatus = Object.assign({}, page.snapshot);
            delete missingStatus.dnsFilterInstalled;
            delete missingStatus.dnsFilterReady;
            page.snapshot = missingStatus;
            page.details = true; test.phase = 23;
        } else if (test.phase === 23 && page && !page.busy) {
            if (!find(page, "repairWebsiteDns").visible || !find(page, "restoreWebsiteDns").visible) { test.fail("recovery hidden without DNS status"); return; }
            find(page, "repairWebsiteDns").clicked();
            find(page, "confirmFirewall").clicked(); test.phase = 22;
        } else if (test.phase === 22 && page && !page.busy && page.success) {
            if (page.snapshot.dnsFilterInstalled || !page.editing) { test.fail("DNS restore"); return; }
            find(page, "setupWebsiteDns").clicked();
            find(page, "confirmFirewall").clicked(); test.phase = 20;
        } else if (test.phase === 20 && page && !page.busy && page.snapshot.dnsFilterReady) {
            if (!page.editing || find(page, "firewallWebsite").text !== "https://www.example.com/page") { test.fail("setup lost draft"); return; }
            let mode = find(page, "dnsMode");
            if (mode.count !== 2 || find(page, "customDnsServers").visible || page.dnsServersDraft !== "") { test.fail("DNS choices or automatic form"); return; }
            mode.currentIndex = 1; mode.activated(1);
            if (!find(page, "customDnsServers").visible || find(page, "applyDnsMode").enabled) { test.fail("empty custom DNS form"); return; }
            let servers = find(page, "customDnsServers"); servers.text = "1.1.1.1, 1.0.0.1"; servers.textEdited();
            if (!page.dnsDirty || !find(page, "applyDnsMode").enabled) { test.fail("custom DNS form"); return; }
            find(page, "applyDnsMode").clicked();
            if (!page.pending || page.pending.operation !== "configure-website-dns") { test.fail("DNS confirmation"); return; }
            find(page, "confirmFirewall").clicked(); test.phase = 24;
        } else if (test.phase === 24 && page && !page.busy) {
            if (!page.success || page.snapshot.dnsMode !== "custom" || page.snapshot.dnsServers[0] !== "1.1.1.1" || page.dnsDirty || !page.editing) { test.fail("custom DNS result or website draft"); return; }
            // Legacy saved providers must display as custom, preserving their addresses.
            page.snapshot = Object.assign({}, page.snapshot, {dnsMode: "family", dnsServers: ["1.1.1.3", "1.0.0.3"]});
            page.resetDnsDraft();
            if (page.dnsModeDraft !== "custom" || page.dnsServersDraft !== "1.1.1.3, 1.0.0.3" || find(page, "dnsModeStatus").text !== "Saved mode: Custom DNS") { test.fail("legacy DNS addresses"); return; }
            let mode = find(page, "dnsMode"); mode.currentIndex = 0; mode.activated(0);
            find(page, "applyDnsMode").clicked(); find(page, "confirmFirewall").clicked(); test.phase = 26;
        } else if (test.phase === 26 && page && !page.busy) {
            if (!page.success || page.snapshot.dnsMode !== "automatic" || !page.snapshot.dnsFilterReady || !page.editing) { test.fail("automatic DNS result"); return; }
            find(page, "saveFirewallRule").clicked(); test.phase = 16;
        } else if (test.phase === 16 && page && !page.busy && !page.dirty) {
            let row = page.rules.find(row => row.kind === "website" && row.value === "example.com");
            if (!page.success || !row || !row.subdomains) { test.fail("add website"); return; }
            find(page, "editFirewall-" + row.id).clicked();
            if (!find(page, "firewallSubdomains").checked) { test.fail("edit lost subdomain option"); return; }
            find(page, "firewallSubdomains").checked = false;
            find(page, "firewallWebsite").text = "other.example";
            find(page, "saveFirewallRule").clicked(); test.phase = 17;
        } else if (test.phase === 17 && page && !page.busy && !page.dirty) {
            if (!page.success || !page.rules.some(row => row.value === "other.example") || page.rules.some(row => row.value === "example.com")) { test.fail("edit website"); return; }
            find(page, "firewallSwitch").clicked();
            if (!page.pending || page.pending.operation !== "disable") { test.fail("off confirmation"); return; }
            find(page, "confirmFirewall").clicked(); test.phase = 7;
        } else if (test.phase === 7 && page && !page.busy && !page.dirty) {
            if (!page.loaded || page.snapshot.running || find(page, "firewallSwitch").checked) { test.fail("off status"); return; }
            let row = page.rules.find(row => row.kind === "website");
            if (!row) { test.fail("website block lost when firewall off"); return; }
            find(page, "removeFirewall-" + row.id).clicked();
            find(page, "confirmFirewall").clicked(); test.phase = 18;
        } else if (test.phase === 18 && page && !page.busy && !page.dirty) {
            if (!page.success || page.rules.some(row => row.kind === "website")) { test.fail("remove website while off"); return; }
            find(page, "firewallSwitch").clicked();
            find(page, "confirmFirewall").clicked(); test.phase = 8;
        } else if (test.phase === 8 && page && !page.busy && !page.dirty) {
            if (!page.snapshot.running || !find(page, "firewallSwitch").checked) { test.fail("on status"); return; }
            window.section = -2; test.phase = 9;
        } else if (test.phase === 9) {
            if (page) { test.fail("clean page retained"); return; }
            deny.running = true; test.phase = 10;
        } else if (test.phase === 10 && !deny.running) { window.section = -22; test.phase = 11; }
        else if (test.phase === 11 && page && !page.busy && !page.success) {
            if (page.loaded || !page.message.includes("Cannot access") || find(page, "firewallSwitch").enabled) { test.fail("access failure"); return; }
            if (window.dirty || window.saving) { test.fail("unrelated settings saved"); return; }
            cancellation.running = true; test.phase = 14;
        } else if (test.phase === 14 && !cancellation.running) {
            find(page, "refreshFirewall").clicked(); test.phase = 15;
        } else if (test.phase === 15 && page && !page.busy) {
            if (!page.message.includes("Authentication cancelled")) { test.fail("cancelled authentication"); return; }
            console.warn("FIREWALL_NATIVE_OK"); Qt.quit();
        }
    } }
    Timer { interval: 15000; running: true; onTriggered: test.fail("timeout") }
}
'''.replace('DENY_PATH', str(root / 'deny')).replace('CANCEL_PATH', str(root / 'cancel-auth')))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='', PATH=str(commands) + os.pathsep + os.environ['PATH'], FIREWALL_TEST_ROOT=str(root))
            result = subprocess.run(['quickshell', '-p', str(fixture)], env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr + '\nEXIT ' + str(result.returncode)
            self.assertIn('FIREWALL_NATIVE_OK', output, output)
            for error in ('FIREWALL_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            self.assertEqual(sum('--add-service=http' in row for row in calls), 2)
            self.assertEqual(sum('--add-service=http' in row and '--permanent' in row for row in calls), 1)
            self.assertEqual((root / 'auth-jobs').read_text().splitlines(), ['status', 'add-service', 'edit-rule', 'status', 'edit-rule', 'remove-port', 'setup-website-dns', 'restore-website-dns', 'setup-website-dns', 'configure-website-dns', 'configure-website-dns', 'add-website', 'edit-website', 'disable', 'remove-website', 'enable', 'status', 'status'])
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
