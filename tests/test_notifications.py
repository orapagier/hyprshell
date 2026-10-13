"""Notification preferences and native delivery use isolated config/state."""
import copy
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('notification_settings', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)


class NotificationSettingsTests(unittest.TestCase):
    def test_defaults_and_saved_preferences(self):
        self.assertFalse(backend.validate({'version': 1})['notifications']['popups'])
        data = copy.deepcopy(backend.DEFAULTS)
        data['notifications'].update(popups=True, doNotDisturb=True, criticalBypass=False,
                                     popupSeconds=12, apps={'org.test.App': 'inbox', 'Other': 'off'})
        self.assertEqual(backend.validate(data), data)

    def test_reject_invalid_preferences(self):
        for key, value in [('popups', 1), ('doNotDisturb', 'yes'), ('criticalBypass', None),
                           ('popupSeconds', 0), ('popupSeconds', 31), ('popupSeconds', 2.5),
                           ('apps', []), ('apps', {'app': 'popup'}), ('apps', {'': 'off'}),
                           ('apps', {'bad\napp': 'off'}), ('unknown', True)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                backend.validate({'version': 1, 'notifications': {key: value}})

    @unittest.skipUnless(shutil.which('quickshell'), 'Native tools required')
    def test_native_popup_delivery_and_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-notifications-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'NotificationsNative.qml'
            entry.write_text((payload / 'tests/NotificationsNative.qml').read_text().replace('import ".."', 'import "."'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='basic', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('NOTIFICATIONS_OK', output, output)
            self.assertNotIn('NOTIFICATIONS_FAILED', output, output)
            self.assertNotIn('TypeError', output, output)
            self.assertNotIn('ReferenceError', output, output)


if __name__ == '__main__':
    unittest.main()
