"""Regional preferences stay in isolated homes and never change system time."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import regional
import preferences


class RegionalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'))
        env.start(); self.addCleanup(env.stop)
        mock = patch.object(regional, 'locales', return_value=['C', 'en_US.utf8']); mock.start(); self.addCleanup(mock.stop)

    def test_saved_language_formats_timezone_preserve_other_environment_blocks(self):
        path, env = regional.paths(); env.parent.mkdir(parents=True)
        env.write_text('export MY_SETTING=keep\n# BEGIN Hyprshell application theme\nexport QT_QPA_PLATFORMTHEME=gtk3\n# END Hyprshell application theme\n')
        data = {'version': 1, 'language': 'en_US.utf8', 'formats': 'C', 'timezone': 'Asia/Manila'}
        regional.save(data, preferences.revision(regional.paths()))
        self.assertEqual(json.loads(path.read_text()), data)
        self.assertIn('export MY_SETTING=keep', env.read_text())
        self.assertIn('export TZ=Asia/Manila', env.read_text())
        self.assertIn('export LC_NUMERIC=C', env.read_text())
        regional.save(regional.DEFAULTS, preferences.revision(regional.paths()))
        self.assertNotIn('export TZ=', env.read_text())
        self.assertEqual(env.read_text().count('BEGIN Hyprshell regional'), 1)

    def test_stale_and_invalid_preferences_write_nothing(self):
        for changes in ({'language': '$(bad)'}, {'language': 'fr_FR.utf8'}, {'timezone': '../etc/passwd'}, {'formats': 'a\nb'}):
            with self.assertRaises(ValueError): regional.save({**regional.DEFAULTS, **changes}, preferences.revision(regional.paths()))
        with self.assertRaises(ValueError): regional.save(regional.DEFAULTS, 'stale')
        self.assertFalse(regional.paths()[0].exists())

    def test_failure_rolls_back_environment_and_restore_skips_missing_locale(self):
        path, env = regional.paths(); env.parent.mkdir(parents=True); env.write_text('export UNRELATED=kept\n')
        atomic = preferences.atomic
        def fail_once(target, text):
            if target == path: raise OSError('disk full')
            return atomic(target, text)
        with patch.object(preferences, 'atomic', side_effect=fail_once), self.assertRaises(OSError):
            regional.save(regional.DEFAULTS, preferences.revision(regional.paths()))
        self.assertEqual(env.read_text(), 'export UNRELATED=kept\n')
        self.assertFalse(path.exists())
        data = {**regional.DEFAULTS, 'language': 'fr_FR.utf8'}
        path.parent.mkdir(parents=True); path.write_text(json.dumps(data))
        with patch.object(regional.subprocess, 'run') as command:
            result = regional.save(data, None, restoring=True)
            command.assert_not_called()
        self.assertEqual(result['skipped'], ['fr_FR.utf8'])
        self.assertEqual(regional.saved(), data)
        self.assertNotIn('fr_FR', env.read_text())

    def test_system_timezone_only_changes_on_explicit_validated_request(self):
        with patch.object(regional.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as command:
            result = regional.request({'operation': 'system-timezone', 'timezone': 'Asia/Manila'})
            self.assertTrue(result['ok'])
            command.assert_called_once_with(['timedatectl', 'set-timezone', 'Asia/Manila'], capture_output=True, text=True, timeout=60)
        self.assertFalse(regional.paths()[0].exists())
        with self.assertRaises(ValueError): regional.request({'operation': 'system-timezone', 'timezone': '--bad'})

    def test_preview_restores_process_locale(self):
        before = regional.locale.setlocale(regional.locale.LC_ALL)
        result = regional.preview({**regional.DEFAULTS, 'formats': 'C', 'timezone': 'UTC'})
        self.assertEqual(result['zone'], 'UTC'); self.assertIn('1234567', result['number'])
        self.assertEqual(regional.locale.setlocale(regional.locale.LC_ALL), before)
        self.assertIn('error', regional.preview({**regional.DEFAULTS, 'formats': 'no_such_locale'}))


if __name__ == '__main__':
    unittest.main()
