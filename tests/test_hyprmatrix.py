"""Check app configuration preservation and the explicit managed sync boundary."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import deployment
import github_sync


class HyprmatrixIntegrationTests(unittest.TestCase):
    def test_updates_retain_user_rain_settings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo = root / 'repo'
            payload = repo / 'config/hyprmatrix/config.toml'
            payload.parent.mkdir(parents=True)
            payload.write_text('opacity = 0.7\n')
            locations = {name: root / name for name in ('home', 'config', 'data', 'state')}
            live = locations['config'] / 'hyprmatrix/config.toml'
            live.parent.mkdir(parents=True)
            live.write_text('opacity = 0.2\nfps = 10\n')
            plan = deployment.inspect(repo, locations)
            self.assertIn('config/hyprmatrix/config.toml', plan['preserved'])
            self.assertEqual(plan['conflicts'], [])
            self.assertEqual(live.read_text(), 'opacity = 0.2\nfps = 10\n')
            live.unlink()
            self.assertIn('config/hyprmatrix/config.toml', deployment.inspect(repo, locations)['changes'])

    def test_explicit_sync_copies_preferences_without_private_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo, config, home = root / 'repo', root / 'config', root / 'home'
            managed = repo / 'config/hyprmatrix/config.toml'
            managed.parent.mkdir(parents=True)
            managed.write_text('fps = 20\n')
            live = config / 'hyprmatrix'
            live.mkdir(parents=True)
            (live / 'config.toml').write_text('fps = 10\n')
            (live / 'private-file').write_text('not a managed setting')
            github_sync.snapshot_managed_files(repo, config, home)
            self.assertEqual(managed.read_text(), 'fps = 10\n')
            self.assertFalse((managed.parent / 'private-file').exists())
            self.assertTrue(github_sync.excluded('hyprmatrix'))
            self.assertFalse(github_sync.excluded('hyprmatrix-rs'))

    def test_source_payload_contains_launcher_and_config_not_build_tree(self):
        files = deployment.payload(ROOT)
        self.assertIn('data/applications/hyprmatrix.desktop', files)
        self.assertIn('config/hyprmatrix/config.toml', files)
        self.assertFalse(any('apps/hyprmatrix-rs/target' in key for key in files))


if __name__ == '__main__':
    unittest.main()
