"""Check login-manager detection without changing the host's services."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LoginManagerTests(unittest.TestCase):
    def test_preserves_configured_and_installed_managers(self):
        source = (ROOT / 'setup.sh').read_text()
        function = source[source.index('login_manager() {'):source.index('\nLOGIN_UNIT=')]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            alias = root / 'display-manager.service'
            function = function.replace('/etc/systemd/system/display-manager.service', str(alias))
            systemctl = root / 'systemctl'
            systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$MANAGER_UNITS"\nexit "${MANAGER_STATUS:-0}"\n')
            systemctl.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'])
            script = 'set -euo pipefail\ndie() { exit 42; }\n' + function + '\nlogin_manager'
            for units, status, expected, manager in [
                ('', '0', 0, ''),
                ('sddm.service disabled disabled', '0', 0, 'sddm.service'),
                ('gdm.service enabled disabled', '0', 0, 'gdm.service'),
                ('greetd.service disabled disabled', '0', 0, 'greetd.service'),
                ('unrelated.service enabled enabled', '0', 0, ''),
                ('sddm.service disabled disabled\ngdm.service enabled enabled', '0', 0, 'gdm.service'),
                ('', '1', 42, ''),
            ]:
                with self.subTest(units=units, status=status):
                    result = subprocess.run(['bash', '-c', script], env=dict(
                        env, MANAGER_UNITS=units, MANAGER_STATUS=status), capture_output=True)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertEqual(result.stdout.decode().strip(), manager)
            alias.symlink_to(root / 'missing-manager.service')
            result = subprocess.run(['bash', '-c', script], env=dict(
                env, MANAGER_UNITS='', MANAGER_STATUS='1'), capture_output=True)
            self.assertEqual(result.returncode, 42)
            alias.unlink()
            target = root / 'sddm.service'; target.touch(); alias.symlink_to(target)
            result = subprocess.run(['bash', '-c', script], env=dict(
                env, MANAGER_UNITS='', MANAGER_STATUS='1'), capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.decode().strip(), 'sddm.service')
