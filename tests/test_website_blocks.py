import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import website_blocks as websites


class WebsiteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.hosts = root / 'hosts'
        self.original = '127.0.0.1 localhost\n::1 localhost\n192.0.2.1 printer.local # keep\n'
        self.hosts.write_text(self.original)
        self.hosts.chmod(0o644)
        self.patches = [patch.object(websites, 'HOSTS', self.hosts), patch.object(websites, 'LOCK', root / 'lock'), patch.object(websites.website_dns, 'status', return_value={'dnsFilterReady': True, 'dnsFilterInstalled': True, 'dnsFilterRevision': 'test'}), patch.object(websites.website_dns, 'apply')]
        for item in self.patches: item.start()

    def tearDown(self):
        for item in self.patches: item.stop()
        self.directory.cleanup()

    def change(self, operation, value, **fields):
        return websites.change({'operation': operation, 'value': value, 'confirmed': True,
                                'expectedWebsite': websites.status()['websiteRevision'], **fields})

    def test_add_edit_remove_preserves_unrelated_entries_and_backup(self):
        self.change('add-website', 'https://www.example.com/some/page')
        self.assertIn('0.0.0.0 example.com www.example.com\n', self.hosts.read_text())
        self.assertIn(':: example.com www.example.com\n', self.hosts.read_text())
        self.assertTrue(self.hosts.read_text().startswith(self.original))
        self.assertEqual(self.hosts.with_name('hosts.hyprshell-websites.bak').read_text(), self.original)
        self.assertEqual(self.hosts.stat().st_mode & 0o777, 0o644)
        self.change('edit-website', 'other.example', old='example.com')
        self.assertNotIn('example.com', self.hosts.read_text())
        self.assertEqual(websites.status()['websites'][0]['value'], 'other.example')
        self.change('remove-website', 'other.example')
        self.assertEqual(self.hosts.read_text(), self.original)

    def test_validation_and_stale_revision_never_write(self):
        for value in ('localhost', '*.example.com', '127.0.0.1', 'example.com\nother.example', '-bad.com', 'example.com:443', 'https://user:password@example.com', 'https://example.com:443', 'https://example.com:bad', None):
            with self.assertRaises(ValueError): self.change('add-website', value)
            self.assertEqual(self.hosts.read_text(), self.original)
        with self.assertRaises(ValueError):
            websites.change({'operation': 'add-website', 'value': 'example.com', 'confirmed': True, 'expectedWebsite': 'stale'})
        with self.assertRaises(ValueError): websites.change({'operation': 'add-website', 'value': 'example.com'})
        self.assertEqual(self.hosts.read_text(), self.original)

    def test_unicode_domains_and_idempotent_duplicates(self):
        self.assertEqual(websites.domain('WWW.Example.COM.'), 'example.com')
        self.assertEqual(websites.domain('bücher.example'), 'xn--bcher-kva.example')
        self.change('add-website', 'example.com')
        text = self.hosts.read_text()
        self.change('add-website', 'www.example.com')
        self.assertEqual(self.hosts.read_text(), text)

    def test_malformed_managed_block_refuses_overwrite(self):
        self.hosts.write_text(self.original + websites.BEGIN + '127.0.0.1 altered.example\n' + websites.END)
        with self.assertRaises(ValueError): websites.status()

    def test_failed_atomic_replace_preserves_hosts(self):
        with patch.object(websites.os, 'replace', side_effect=OSError('write denied')):
            with self.assertRaises(OSError): self.change('add-website', 'example.com')
        self.assertEqual(self.hosts.read_text(), self.original)
        self.assertEqual(list(self.hosts.parent.glob('.hyprshell-websites-*')), [])

    def test_failure_replacing_hosts_keeps_original_and_backup(self):
        original_replace = websites.os.replace
        def replace(source, destination):
            if Path(destination) == self.hosts:
                raise OSError('replace denied')
            original_replace(source, destination)
        with patch.object(websites.os, 'replace', side_effect=replace):
            with self.assertRaises(OSError): self.change('add-website', 'example.com')
        self.assertEqual(self.hosts.read_text(), self.original)
        self.assertEqual(self.hosts.with_name('hosts.hyprshell-websites.bak').read_text(), self.original)

    def test_website_change_remains_successful_when_firewalld_unavailable(self):
        import firewall
        with patch.object(firewall, 'request_firewall', side_effect=ValueError('unavailable')):
            result = firewall.request({'operation': 'add-website', 'value': 'example.com', 'confirmed': True, 'expectedWebsite': websites.status()['websiteRevision']})
        self.assertTrue(result['ok']); self.assertTrue(result['firewallUnavailable'])
        self.assertEqual(result['websites'][0]['value'], 'example.com')

    def test_system_hosts_change_during_backup_is_not_overwritten(self):
        original_atomic = websites.atomic
        def atomic(path, text, metadata, private=False):
            original_atomic(path, text, metadata, private)
            if private:
                self.hosts.write_text(self.original + '192.0.2.4 new-device.local\n')
        with patch.object(websites, 'atomic', side_effect=atomic):
            with self.assertRaisesRegex(ValueError, 'changed'):
                self.change('add-website', 'example.com')
        self.assertIn('new-device.local', self.hosts.read_text())
        self.assertNotIn('www.example.com', self.hosts.read_text())

    def test_subdomains_default_on_and_edit_can_turn_them_off(self):
        self.change('add-website', 'example.com')
        self.assertTrue(websites.status()['websites'][0]['subdomains'])
        websites.website_dns.apply.assert_called_with({'example.com': True})
        self.change('edit-website', 'example.com', old='example.com', subdomains=False)
        self.assertFalse(websites.status()['websites'][0]['subdomains'])
        websites.website_dns.apply.assert_called_with({'example.com': False})

    def test_legacy_exact_entries_remain_exact(self):
        self.hosts.write_text(self.original + websites.content(['example.com'], legacy=True))
        self.assertFalse(websites.status()['websites'][0]['subdomains'])

    def test_default_wildcard_save_rejected_before_writing_without_filter(self):
        with patch.object(websites.website_dns, 'status', return_value={'dnsFilterReady': False, 'dnsFilterInstalled': False, 'dnsFilterRevision': 'test'}):
            with self.assertRaisesRegex(ValueError, 'Set up'):
                self.change('add-website', 'example.com')
        self.assertEqual(self.hosts.read_text(), self.original)
        websites.website_dns.apply.assert_not_called()

    def test_dns_update_failure_restores_hosts(self):
        with patch.object(websites.website_dns, 'apply', side_effect=ValueError('dns failed')):
            with self.assertRaises(ValueError): self.change('add-website', 'example.com')
        self.assertEqual(self.hosts.read_text(), self.original)

    def test_symlink_is_rejected(self):
        target = self.hosts.with_name('target'); self.hosts.rename(target); self.hosts.symlink_to(target)
        with self.assertRaises(ValueError): websites.status()
        self.assertEqual(target.read_text(), self.original)

    def test_dns_mode_change_rejects_stale_website_revision(self):
        with patch.object(websites.website_dns, 'configure') as configure:
            with self.assertRaisesRegex(ValueError, 'changed'):
                websites.dns_change('configure-website-dns', {'mode': 'family', 'expectedWebsite': 'stale'})
            configure.assert_not_called()
            websites.dns_change('configure-website-dns', {'mode': 'custom', 'servers': '1.1.1.1', 'expectedWebsite': websites.status()['websiteRevision']})
            configure.assert_called_once_with({}, 'custom', '1.1.1.1')
