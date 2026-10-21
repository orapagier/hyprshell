"""Pinned app downloads and real deployment transactions, without network or Cargo."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import app_releases
import deployment


def elf(label):
    data = bytearray(64)
    data[:7] = b'\x7fELF\x02\x01\x01'
    data[16:18] = (3).to_bytes(2, 'little')
    data[18:20] = (62).to_bytes(2, 'little')
    return bytes(data) + label.encode()


class Response(io.BytesIO):
    def geturl(self):
        return 'https://release-assets.githubusercontent.com/test'


class AppReleaseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.locations = {name: self.root / name for name in ('home', 'config', 'data', 'state')}
        self.stage = self.root / 'stage'
        self.binaries = {app: elf(app) for app in app_releases.APPS}
        self.manifest = {'format': 1, 'repository': 'example/hyprshell', 'tag': 'desktop-apps-v1',
                         'architectures': {'x86_64': {app: {
                             'asset': app + '-linux-x86_64',
                             'sha256': hashlib.sha256(data).hexdigest(), 'minimum_glibc': '2.43'}
                             for app, data in self.binaries.items()}}}
        self.save_manifest()
        for name, value in [('system', 'Linux'), ('machine', 'x86_64'), ('libc_ver', ('glibc', '2.43'))]:
            patcher = patch.object(app_releases.platform, name, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def save_manifest(self):
        (self.repo / 'app-releases.json').write_text(json.dumps(self.manifest))

    def download(self, request, timeout):
        self.assertEqual(timeout, 60)
        url = request.full_url
        app = url.rsplit('/', 1)[1].removesuffix('-linux-x86_64')
        self.assertEqual(url, 'https://github.com/example/hyprshell/releases/download/'
                         'desktop-apps-v1/' + app + '-linux-x86_64')
        return Response(self.binaries[app])

    def stage_apps(self):
        return app_releases.stage_apps(self.repo, self.stage, self.locations)

    def installed_path(self, app):
        root, relative = app_releases.TARGETS[app].split('/', 1)
        return self.locations[root] / relative

    def test_downloads_pinned_assets_and_marks_them_executable(self):
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=self.download) as fetch:
            staged = self.stage_apps()
        self.assertEqual(fetch.call_count, 3)
        for app, data in self.binaries.items():
            target = staged[app_releases.TARGETS[app]]
            self.assertEqual(target.read_bytes(), data)
            self.assertEqual(target.stat().st_mode & 0o777, 0o755)
        self.assertFalse(self.locations['home'].exists())
        self.assertFalse(self.locations['config'].exists())

    def test_reuses_only_installed_binaries_with_matching_checksums(self):
        for app, data in self.binaries.items():
            installed = self.installed_path(app)
            installed.parent.mkdir(parents=True, exist_ok=True)
            installed.write_bytes(data)
        with patch.object(app_releases.urllib.request, 'urlopen') as fetch:
            self.stage_apps()
            fetch.assert_not_called()
        (self.locations['home'] / '.local/bin/hyprmatrix').write_bytes(b'older release')
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=self.download) as fetch:
            self.stage_apps()
            self.assertEqual(fetch.call_count, 1)

    def test_bad_checksum_and_html_download_never_install(self):
        with patch.object(app_releases.urllib.request, 'urlopen', return_value=Response(b'corrupt')):
            with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                self.stage_apps()
        html = b'<html>download failed</html>'
        self.manifest['architectures']['x86_64']['hyprmonitor']['sha256'] = hashlib.sha256(html).hexdigest()
        self.save_manifest()
        with patch.object(app_releases.urllib.request, 'urlopen', return_value=Response(html)):
            with self.assertRaisesRegex(RuntimeError, 'ELF executable'):
                self.stage_apps()
        self.assertFalse(self.locations['home'].exists())

    def test_unsupported_platform_or_glibc_stops_before_download(self):
        with patch.object(app_releases.urllib.request, 'urlopen') as fetch:
            for name, value, message in [('machine', 'aarch64', 'No desktop app release'),
                                         ('libc_ver', ('glibc', '2.42'), 'requires glibc 2.43'),
                                         ('libc_ver', ('musl', '1.2.5'), 'require Linux with glibc')]:
                with self.subTest(value=value), patch.object(app_releases.platform, name, return_value=value):
                    with self.assertRaisesRegex(RuntimeError, message):
                        self.stage_apps()
            fetch.assert_not_called()

    def test_missing_asset_reports_retry_without_source_fallback(self):
        error = urllib.error.HTTPError('url', 404, 'not found', {}, None)
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=error):
            with self.assertRaisesRegex(RuntimeError, 'Publish the release asset.*No Cargo fallback'):
                self.stage_apps()
        error.close()

    def test_manifest_rejects_bad_tag_asset_and_hash(self):
        for field, value in [('tag', '../latest'), ('asset', '../../bad'), ('sha256', 'invalid')]:
            with self.subTest(field=field):
                old = self.manifest['tag'] if field == 'tag' else self.manifest['architectures']['x86_64']['hyprmonitor'][field]
                if field == 'tag':
                    self.manifest[field] = value
                else:
                    self.manifest['architectures']['x86_64']['hyprmonitor'][field] = value
                self.save_manifest()
                with patch.object(app_releases.urllib.request, 'urlopen') as fetch:
                    with self.assertRaisesRegex(RuntimeError, 'Invalid desktop app release'):
                        self.stage_apps()
                    fetch.assert_not_called()
                if field == 'tag':
                    self.manifest[field] = old
                else:
                    self.manifest['architectures']['x86_64']['hyprmonitor'][field] = old

    def prepare_deployment(self):
        source = self.repo / 'config/quickshell/shell.qml'
        source.parent.mkdir(parents=True)
        source.write_text('// old shell\n')
        helper = self.repo / 'config/quickshell/helpers/audio-spectrum.c'
        helper.parent.mkdir()
        helper.write_text('/* fixture */\n')
        for app in app_releases.APPS:
            manifest = self.repo / 'apps' / (app + '-rs/Cargo.toml')
            manifest.parent.mkdir(parents=True)
            manifest.write_text('[package]\nname = "' + app + '"\n')

    def compile_helper(self, args, **kwargs):
        if args[0] == 'git':
            return subprocess.CompletedProcess(args, 1, stdout=b'', stderr=b'fixture has no Git history')
        self.assertEqual(args[0], 'cc', 'App installation must not invoke Cargo')
        Path(args[args.index('-o') + 1]).write_bytes(b'audio helper')
        return subprocess.CompletedProcess(args, 0)

    def install(self):
        with patch.object(deployment.subprocess, 'run', side_effect=self.compile_helper), \
                patch.object(deployment, 'validate_staged'):
            return deployment.install(self.repo, locations=self.locations, build={'revision': 'test'})

    def test_real_deployment_installs_without_cargo_and_rolls_back(self):
        self.prepare_deployment()
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=self.download):
            result = self.install()
        for app, data in self.binaries.items():
            self.assertIn(app_releases.TARGETS[app], result['changed'])
            self.assertEqual(self.installed_path(app).read_bytes(), data)
        deployment.rollback(Path(result['backup']), self.locations)
        for app in app_releases.APPS:
            self.assertFalse(self.installed_path(app).exists())

    def test_download_failure_preserves_all_live_files_and_deployment_manifest(self):
        self.prepare_deployment()
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=self.download):
            self.install()
        old_manifest = (self.locations['state'] / 'deployed.json').read_bytes()
        old_shell = (self.locations['config'] / 'quickshell/shell.qml').read_bytes()
        (self.repo / 'config/quickshell/shell.qml').write_text('// new shell\n')
        self.manifest['architectures']['x86_64']['hyprweather']['sha256'] = '0' * 64
        self.save_manifest()
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=OSError('offline')):
            with self.assertRaisesRegex(RuntimeError, 'Could not download hyprweather'):
                self.install()
        self.assertEqual((self.locations['state'] / 'deployed.json').read_bytes(), old_manifest)
        self.assertEqual((self.locations['config'] / 'quickshell/shell.qml').read_bytes(), old_shell)
        for app, data in self.binaries.items():
            self.assertEqual(self.installed_path(app).read_bytes(), data)

    def test_concurrent_binary_edit_is_preserved(self):
        self.prepare_deployment()
        def download(request, timeout):
            installed = self.locations['home'] / '.local/bin/hyprmonitor'
            installed.parent.mkdir(parents=True, exist_ok=True)
            installed.write_bytes(b'concurrent edit')
            return self.download(request, timeout)
        with patch.object(app_releases.urllib.request, 'urlopen', side_effect=download):
            with self.assertRaisesRegex(RuntimeError, 'changed during validation'):
                self.install()
        self.assertEqual((self.locations['home'] / '.local/bin/hyprmonitor').read_bytes(), b'concurrent edit')
        self.assertFalse((self.locations['config'] / 'quickshell/shell.qml').exists())


if __name__ == '__main__':
    unittest.main()
