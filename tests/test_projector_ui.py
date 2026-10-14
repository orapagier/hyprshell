"""Verify projection controls and confirmation with isolated display helpers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class ProjectorUiTests(unittest.TestCase):
    def test_projector_and_advanced_display_controls(self):
        for fixture, marker in [('ProjectorNative', 'PROJECTOR_NATIVE_OK'),
                                ('SettingsDisplaysNative', 'DISPLAYS_NATIVE_OK')]:
            with self.subTest(fixture=fixture), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = root / 'config/quickshell'
                shutil.copytree(ROOT / 'config/quickshell', payload,
                                ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
                # Offscreen Qt has no layer-shell backend. Keep the actual card
                # and controls, using a native window only in this isolated copy.
                projector = payload / 'ProjectorWindow.qml'
                source = projector.read_text().replace('PanelWindow {', 'FloatingWindow {')
                source = source.replace('    anchors { top: true; bottom: true; left: true; right: true }',
                                        '    implicitWidth: 800; implicitHeight: 600')
                source = '\n'.join(line for line in source.splitlines()
                                   if 'exclusionMode:' not in line and 'WlrLayershell.' not in line) + '\n'
                projector.write_text(source)
                (payload / 'settings/displays.py').write_text('''import json, sys
p = json.loads(sys.argv[2])
def emit(data):
    print(json.dumps(dict(ok=True, **data)), flush=True)
if p['operation'] == 'status':
    emit(dict(monitors=[dict(name='eDP-1', width=1920, height=1080, scale=1, x=0, y=0,
        availableModes=['1920x1080@60.00Hz', '1920x1080@120.00Hz', '1280x720@60.00Hz'])],
        entries=[dict(output='eDP-1', mode='1920x1080@60.00Hz', scale=1, transform=0, position='auto', mirror='')],
        saved=dict(version=1, entries=[])))
else:
    emit(dict(pending=True, seconds=15))
    decision = sys.stdin.readline().strip()
    emit(dict(pending=False, message='Display settings saved.' if decision == 'keep'
        else 'Previous display settings restored.'))
''')
                entry = payload / (fixture + '.qml')
                entry.write_text((payload / 'tests' / entry.name).read_text().replace('import ".."', 'import "."'))
                runtime = root / 'runtime'
                runtime.mkdir(mode=0o700)
                env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                           XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                           QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
                result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)], env=env,
                                        capture_output=True, text=True, timeout=16)
                output = result.stdout + result.stderr
                self.assertIn(marker, output, output)
                self.assertEqual(result.returncode, 0, output)
                for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', '_FAILED'):
                    self.assertNotIn(error, output, output)
