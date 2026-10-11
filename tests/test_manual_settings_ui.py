"""Exercise retained manual drafts without changing any desktop preferences."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class ManualDraftTests(unittest.TestCase):
    def test_navigation_close_reopen_and_explicit_save(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            stub = '''import json, sys
from pathlib import Path
p = json.loads(sys.argv[2])
if Path(__file__).stem == 'behavior':
    settings = p['settings'] if p['operation'] == 'save' else {'version': 1, 'general': {}, 'workspaces': [], 'rules': []}
    result = dict(settings=settings, classes=[], discoveryMessage='', revision='test')
else:
    settings = {'version': 1, 'language': '', 'formats': '', 'timezone': ''}
    result = dict(settings=settings, locales=['en_US.UTF-8'], timezones=['Asia/Manila'], revision='test')
print(json.dumps(dict(ok=True, **result)))
'''
            for name in ('behavior', 'regional'):
                (payload / 'settings' / (name + '.py')).write_text(stub)
            entry = payload / 'SettingsManualDrafts.qml'
            entry.write_text((payload / 'tests/SettingsManualDrafts.qml').read_text().replace('import ".."', 'import "."'))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], capture_output=True, text=True, env=env, timeout=16)
            output = result.stdout + result.stderr
            self.assertIn('MANUAL_DRAFT_OK', output, output)
            self.assertEqual(result.returncode, 0, output)
            for error in ('MANUAL_DRAFT_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output, output)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
