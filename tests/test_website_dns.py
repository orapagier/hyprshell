from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import website_dns as dns


class DnsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.paths = {name: root / name for name in ('NM', 'RESOLVED', 'RULES', 'STATE', 'RESOLV')}
        stub = root / 'run/systemd/resolve/stub-resolv.conf'; stub.parent.mkdir(parents=True); stub.touch()
        self.paths['RESOLV'].symlink_to(stub)
        def command(args, timeout=30):
            if args[0] == 'NetworkManager': return dns.NM.read_text() if dns.NM.exists() else '[main]\ndns=systemd-resolved\n'
            if args[0] == 'systemd-analyze': return '[Resolve]\n'
            return ''
        self.nmcli_executable = dns.shutil.which('nmcli')
        self.nm_executable = dns.shutil.which('NetworkManager')
        self.real_probe = dns.probe
        self.patches = [patch.object(dns, name, path) for name, path in self.paths.items()]
        self.patches += [patch.object(dns, 'command', side_effect=command), patch.object(dns.shutil, 'which', side_effect=lambda name: '/test/dnsmasq' if name == 'dnsmasq' else None), patch.object(dns, 'probe', side_effect=lambda name, server='127.0.0.1': 3 if name.startswith('hyprshell-check-') else 0)]
        for item in self.patches: item.start()

    def tearDown(self):
        for item in self.patches: item.stop()
        self.directory.cleanup()

    def test_suffix_rules_block_all_record_types_only_when_enabled(self):
        text = dns.generated({'example.com': True, 'exact.example': False})
        self.assertIn('local=/example.com/\n', text)
        self.assertNotIn('exact.example', text)
        self.assertNotIn('log-queries', text)

    def test_setup_keeps_resolved_and_restores_original_link(self):
        link = dns.RESOLV.readlink()
        dns.setup({'example.com': True})
        self.assertTrue(dns.status()['dnsFilterReady'])
        self.assertEqual(str(dns.RESOLV.readlink()), dns.FILTER_RESOLV)
        self.assertIn('rc-manager=symlink', dns.NM.read_text())
        self.assertNotIn('DNS=', dns.RESOLVED.read_text().replace('FallbackDNS=', ''))
        dns.restore()
        self.assertFalse(dns.status()['dnsFilterReady'])
        for name in ('NM', 'RESOLVED', 'RULES'): self.assertFalse(self.paths[name].exists())
        self.assertEqual(dns.RESOLV.readlink(), link)

    def test_setup_activation_failure_removes_snippets_and_receipt(self):
        with patch.object(dns, 'verify', side_effect=ValueError('dns failed')):
            with self.assertRaisesRegex(ValueError, 'Original DNS configuration was restored'):
                dns.setup({'example.com': True})
        for name in ('NM', 'RESOLVED', 'RULES'): self.assertFalse(self.paths[name].exists())
        self.assertFalse((dns.STATE / 'installed.json').exists())

    def test_rule_update_failure_restores_previous_rules(self):
        dns.setup({'example.com': True})
        text = dns.RULES.read_text()
        with patch.object(dns, 'verify', side_effect=ValueError('dns failed')):
            with self.assertRaisesRegex(ValueError, 'previous filter rules were restored'):
                dns.apply({'other.example': True})
        self.assertEqual(dns.RULES.read_text(), text)

    def test_custom_security_dns_and_other_providers_are_not_replaced(self):
        for text in ('[Resolve]\nDNSOverTLS=yes\n', '[Resolve]\nDNS=9.9.9.9\n', '[Resolve]\nDNSSEC=yes\n'):
            with patch.object(dns, 'command', side_effect=lambda args, timeout=30: text if args[0] == 'systemd-analyze' else ''):
                with self.assertRaises(ValueError): dns.preflight()
        with patch.object(dns, 'command', side_effect=lambda args, timeout=30: '[main]\ndns=none\n' if args[0] == 'NetworkManager' else ''):
            with self.assertRaises(ValueError): dns.preflight()
        self.assertFalse(dns.NM.exists())

    def test_managed_path_collision_and_changed_files_refuse_overwrite(self):
        dns.NM.write_text('unrelated config')
        with self.assertRaises(ValueError): dns.setup({})
        self.assertEqual(dns.NM.read_text(), 'unrelated config')
        dns.NM.unlink(); dns.setup({})
        dns.NM.write_text('changed config')
        with self.assertRaises(ValueError): dns.restore()
        self.assertEqual(dns.NM.read_text(), 'changed config')

    def test_activation_retries_only_while_services_start(self):
        with patch.object(dns, 'verify_once', side_effect=[ConnectionRefusedError(), ValueError('not ready'), None]) as once, patch.object(dns.time, 'sleep') as sleep:
            dns.verify({'example.com': True})
        self.assertEqual(once.call_count, 3); self.assertEqual(sleep.call_count, 2)

    def test_changed_rule_file_is_not_claimed_active_or_deleted(self):
        dns.setup({'example.com': True})
        dns.RULES.write_text(dns.RULES.read_text() + 'local=/manual.example/\n')
        self.assertFalse(dns.status()['dnsFilterReady'])
        with self.assertRaises(ValueError): dns.restore()
        self.assertIn('manual.example', dns.RULES.read_text())

    def test_active_dns_security_profile_or_dns_server_requires_review(self):
        def config(args, timeout=30):
            if args[0] == 'nmcli' and '--fields' in args: return 'test-profile'
            if args[0] == 'nmcli' and '--get-values' in args: return '2 (yes)'
            return ''
        with patch.object(dns, 'command', side_effect=config):
            with self.assertRaises(ValueError): dns.preflight()
        with patch.object(dns, 'command', side_effect=lambda args, timeout=30: 'UNCONN 0 0 127.0.0.1:53 0.0.0.0:*' if args[0] == 'ss' else ''):
            with self.assertRaises(ValueError): dns.preflight()

    def test_reload_uses_comma_flags_and_restores_servers_after_restart(self):
        dns.reload()
        self.assertEqual([call.args[0] for call in dns.command.call_args_list], [
            ['systemctl', 'restart', 'systemd-resolved.service'],
            ['nmcli', 'general', 'reload', 'conf,dns-full']])
        dns.command.reset_mock(); dns.NM.write_text(dns.NM_CONTENT)
        dns.reload()
        self.assertEqual([call.args[0] for call in dns.command.call_args_list], [
            ['nmcli', 'general', 'reload', 'conf,dns-full'],
            ['systemctl', 'restart', 'systemd-resolved.service']])

    def test_real_nmcli_accepts_the_reload_arguments_without_a_system_bus(self):
        import os, shutil, subprocess
        if not self.nmcli_executable: self.skipTest('nmcli missing')
        dns.reload()
        args = next(call.args[0] for call in dns.command.call_args_list if call.args[0][0] == 'nmcli')
        args[0] = self.nmcli_executable
        # A nonexistent private bus prevents any real DNS/network mutation.
        result = subprocess.run(args, capture_output=True, text=True, timeout=10,
                                env=dict(os.environ, LC_ALL='C', DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(self.paths['STATE'] / 'no-system-bus')))
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('extra argument', output.lower())
        self.assertNotIn('invalid argument', output.lower())
        self.assertTrue(any(term in output.lower() for term in ('connect', 'bus', 'nmclient')), output)

    def test_failed_setup_receipt_can_restore_then_retry(self):
        with patch.object(dns, 'reload', side_effect=ValueError('NetworkManager DNS reload failed (exit 2).')):
            with self.assertRaisesRegex(ValueError, 'Recovery failed'):
                dns.setup({})
        self.assertTrue(dns.status()['dnsFilterInstalled'])
        self.assertFalse(dns.status()['dnsFilterReady'])
        self.assertFalse(dns.NM.exists())
        dns.restore()
        self.assertFalse(dns.status()['dnsFilterInstalled'])
        dns.setup({})
        self.assertTrue(dns.status()['dnsFilterReady'])

    def test_filter_queries_validate_reply_id_and_rcode(self):
        from unittest.mock import MagicMock
        client = MagicMock()
        client.recv.return_value = b'\x12\x34\x81\x83' + b'\0' * 8
        socket = MagicMock(); socket.__enter__.return_value = client
        with patch.object(dns.os, 'urandom', return_value=b'\x12\x34'), patch.object(dns.socket, 'socket', return_value=socket):
            self.assertEqual(self.real_probe('child.example.com'), 3)
            packet = client.send.call_args.args[0]
            self.assertIn(b'\x05child\x07example\x03com\0', packet)
            client.recv.return_value = b'\x00\x00\x81\x83' + b'\0' * 8
            with self.assertRaises(ValueError): self.real_probe('child.example.com')

    def test_custom_and_protection_modes_preserve_blocks_and_restore(self):
        import json
        original = dns.RESOLV.readlink()
        dns.configure({'example.com': True}, 'custom', '1.1.1.1, 2606:4700:4700::1111')
        self.assertEqual(dns.status()['dnsServers'], ['1.1.1.1', '2606:4700:4700::1111'])
        self.assertTrue(dns.status()['dnsFilterReady'])
        original_revision = dns.status()['dnsFilterRevision']
        for mode in ('malicious', 'family'):
            dns.apply({'example.com': True})
            dns.configure({'example.com': True}, mode)
            self.assertEqual(dns.status()['dnsMode'], mode)
            self.assertEqual(dns.status()['dnsServers'], dns.PRESETS[mode])
            self.assertIn('servers=' + ','.join(dns.PRESETS[mode]), dns.NM.read_text())
            self.assertIn('local=/example.com/', dns.RULES.read_text())
            self.assertNotEqual(dns.status()['dnsFilterRevision'], original_revision)
            dns.apply({'other.example': True})
            self.assertEqual(dns.status()['dnsMode'], mode)
        dns.configure({'other.example': True}, 'automatic')
        self.assertNotIn('global-dns', dns.NM.read_text())
        self.assertTrue(dns.status()['dnsFilterReady'])
        self.assertIn('local=/other.example/', dns.RULES.read_text())
        dns.restore()
        self.assertEqual(dns.RESOLV.readlink(), original)

    def test_invalid_dns_selection_never_touches_configuration(self):
        for mode, servers in [('invalid', []), ([], []), ('custom', []), ('custom', ['1.1.1.1'] * 9), ('custom', '1.1.1.1\nserver=/evil/8.8.8.8'), ('custom', 'https://dns.example'), ('custom', '127.0.0.1'), ('custom', '127.0.0.53'), ('custom', '::1'), ('custom', '0.0.0.0'), ('custom', '224.0.0.1'), ('custom', 'fe80::1%wlan0'), ('custom', '::ffff:127.0.0.1')]:
            with self.subTest(mode=mode, servers=servers), self.assertRaises(ValueError):
                dns.configure({}, mode, servers)
            self.assertFalse(dns.NM.exists())
        self.assertEqual(dns.selection('custom', '192.168.1.1 1.1.1.1;1.1.1.1'), ('custom', ['192.168.1.1', '1.1.1.1']))

    def test_failed_mode_change_restores_mode_receipt_and_blocks(self):
        dns.configure({'example.com': True}, 'family')
        before = {p: p.read_bytes() for p in (dns.NM, dns.RULES, dns.STATE / 'installed.json')}
        with patch.object(dns, 'verify', side_effect=ValueError('DNS unavailable')):
            with self.assertRaisesRegex(ValueError, 'Previous DNS mode was restored'):
                dns.configure({'example.com': True}, 'custom', '192.0.2.123')
        for path, text in before.items(): self.assertEqual(path.read_bytes(), text)
        self.assertEqual(dns.status()['dnsMode'], 'family')
        self.assertTrue(dns.status()['dnsFilterReady'])

    def test_unrelated_domain_nxdomain_is_not_a_successful_connection_check(self):
        with patch.object(dns, 'probe', return_value=3):
            with self.assertRaisesRegex(ValueError, 'Normal DNS lookup'):
                dns.verify_once({})

    def test_external_networkmanager_override_rolls_back(self):
        dns.setup({})
        old = dns.NM.read_text()
        def command(args, timeout=30):
            return old if args[0] == 'NetworkManager' else ''
        with patch.object(dns, 'command', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'Previous DNS mode was restored'):
                dns.configure({}, 'family')
        self.assertEqual(dns.NM.read_text(), old)
        self.assertEqual(dns.status()['dnsMode'], 'automatic')

    def test_interrupted_mode_change_can_restore_either_managed_configuration(self):
        import json
        for write_new in (False, True):
            dns.setup({})
            receipt = dns.STATE / 'installed.json'
            record = json.loads(receipt.read_text())
            record.update(phase='changing', mode='family', servers=dns.PRESETS['family'], previousMode='automatic', previousServers=[])
            receipt.write_text(json.dumps(record))
            if write_new: dns.NM.write_text(dns.nm_content('family'))
            self.assertFalse(dns.status()['dnsFilterReady'])
            dns.restore()
            self.assertFalse(dns.status()['dnsFilterInstalled'])

    def test_automatic_without_filter_does_not_install_or_modify_dns(self):
        self.assertEqual(dns.configure({}, 'automatic')['dnsMode'], 'automatic')
        self.assertFalse(dns.NM.exists())
        self.assertEqual(dns.command.call_count, 0)

    def test_installed_networkmanager_accepts_all_mode_configurations(self):
        import subprocess
        if not self.nm_executable: self.skipTest('NetworkManager missing')
        root = Path(self.directory.name)
        empty = root / 'empty'; empty.mkdir()
        for mode, servers in [('automatic', []), ('custom', ['1.1.1.1', '2606:4700:4700::1111']), ('malicious', dns.PRESETS['malicious']), ('family', dns.PRESETS['family'])]:
            with self.subTest(mode=mode):
                config = root / 'parser.conf'; config.write_text(dns.nm_content(mode, servers))
                # Print only: isolated configs, no service start or network changes.
                result = subprocess.run([self.nm_executable, '--print-config', '--config=' + str(config), '--config-dir=' + str(empty), '--system-config-dir=' + str(empty), '--intern-config=' + str(root / 'internal.conf')], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                with patch.object(dns, 'command', return_value=result.stdout):
                    dns.verify_configuration(mode, servers)
