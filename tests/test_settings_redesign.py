"""Render the settings redesign in isolation without changing desktop preferences."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class SettingsRedesignTests(unittest.TestCase):
    def test_bluetooth_controls_without_a_real_radio(self):
        with tempfile.TemporaryDirectory(prefix='hyprsettings-bluetooth-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'BluetoothTest.qml'
            entry.write_text((payload / 'tests/SettingsBluetoothNative.qml').read_text()
                             .replace('import ".."', 'import "."'))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(root / 'no-bus'),
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('BLUETOOTH_OK', output, output)
            for error in ('TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)

    def test_navigation_bluetooth_accessibility_and_responsive_rendering(self):
        with tempfile.TemporaryDirectory(prefix='hyprsettings-design-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'SettingsRedesign.qml'
            entry.write_text((payload / 'tests/SettingsRedesign.qml').read_text()
                             .replace('import ".."', 'import "."').replace('import "../', 'import "./'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            captures = Path(os.environ.get('HYPRSETTINGS_CAPTURE_DIR', str(root / 'captures')))
            captures.mkdir(parents=True, exist_ok=True)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(root / 'no-system-bus'),
                       HYPRSETTINGS_CAPTURE_DIR=str(captures), QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('REDESIGN_OK', output, output)
            for error in ('REDESIGN_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            for name in ('overview', 'input', 'bluetooth', 'narrow', 'accessible'):
                self.assertGreater((captures / (name + '.png')).stat().st_size, 2000)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
