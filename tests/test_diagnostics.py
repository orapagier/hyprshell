"""Diagnostic reports use fixed metadata and never collect personal content."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import diagnostics


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'))
        env.start(); self.addCleanup(env.stop)

    def test_permission_failure_is_unavailable_and_raw_output_is_not_copied(self):
        private = 'token=PRIVATE 192.168.10.1 secret-SSID /home/private/file'
        def invoke(args):
            return (0, private) if args[0] == 'hyprctl' else (1, private)
        with patch.object(diagnostics, 'invoke', side_effect=invoke), patch.object(diagnostics.shutil, 'which', return_value='/bin/fake'):
            report = diagnostics.check()
        self.assertEqual(report['checks'][0]['state'], 'unavailable')
        self.assertEqual(report['checks'][-1]['state'], 'attention')
        self.assertNotIn(private, json.dumps(report))
        self.assertNotIn('/home/', json.dumps(report))

    def test_explicit_export_is_private_and_does_not_export_configuration(self):
        path = self.root / 'config/hyprshell/settings.json'; path.parent.mkdir(parents=True)
        path.write_text('{"version":1,"locking":{"command":"private-token-value"}}')
        with patch.object(diagnostics, 'invoke', return_value=(0, 'active')), patch.object(diagnostics.shutil, 'which', return_value='/bin/fake'):
            result = diagnostics.request({'operation': 'export'})
        report = Path(result['path'])
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('private-token-value', report.read_text())
        self.assertEqual(set(json.loads(report.read_text())), {'version', 'created', 'system', 'checks'})

    def test_getting_started_has_no_health_checks_until_requested(self):
        with patch.object(diagnostics, 'check') as check:
            self.assertFalse(diagnostics.request({'operation': 'status'})['guideComplete'])
            self.assertTrue(diagnostics.request({'operation': 'guide-complete'})['guideComplete'])
            self.assertTrue(diagnostics.request({'operation': 'status'})['guideComplete'])
            check.assert_not_called()
        self.assertFalse((self.root / 'config').exists())


if __name__ == '__main__':
    unittest.main()
