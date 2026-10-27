"""Run the real Wi-Fi probe and UI with deterministic curl responses, offline."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class WifiInternetTests(unittest.TestCase):
    def test_native_connectivity_and_indicators(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-wifi-test-') as directory:
            root = Path(directory)
            executable = root / 'curl'
            executable.write_text('''#!/usr/bin/python3
import sys
interface = sys.argv[sys.argv.index('--interface') + 1]
assert '--noproxy' in sys.argv and '--max-time' in sys.argv
if interface == 'test-offline': sys.exit(28)
print('<html>Sign in</html>' if interface == 'test-portal' else 'NetworkManager is online')
''')
            executable.chmod(0o700)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            payload = root / 'payload'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'WifiInternetNative.qml'
            entry.write_text((payload / 'tests/WifiInternetNative.qml').read_text().replace('import ".."', 'import "."'))
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run([
                'quickshell', '--log-rules', 'qml=true', '-p', str(entry)
            ], env=env, text=True, capture_output=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn('WIFI_FAIL', output)
            self.assertIn('WIFI_PASS', output)


if __name__ == '__main__':
    unittest.main()
