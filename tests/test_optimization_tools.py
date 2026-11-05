from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path):
    import compare_shell_measurements as compare
    import profile_app_icons as icons


class AcceptanceGatesTests(unittest.TestCase):
    def test_gain_must_exceed_twice_larger_variation(self):
        result = compare.gate([100, 102, 101], [96, 97, 98], absolute=1)
        self.assertEqual(result['status'], 'inconclusive')
        self.assertEqual(result['improvement_mib'], 4)
        result = compare.gate([100, 101, 100], [93, 94, 93], absolute=5)
        self.assertEqual(result['status'], 'metric_pass')

    def test_absolute_and_relative_helper_gates_both_apply(self):
        self.assertEqual(compare.gate([40]*3, [34]*3, absolute=5, percent=25)['status'], 'inconclusive')
        self.assertEqual(compare.gate([40]*3, [30]*3, absolute=5, percent=25)['status'], 'metric_pass')
        self.assertEqual(compare.gate([8]*3, [5]*3, absolute=5, percent=25)['status'], 'inconclusive')

    def test_invalid_or_insufficient_evidence_rejected(self):
        for before, after in [([10]*2, [1]*2), ([10]*3, [1]*4),
                              ([10]*3, [None]*3), ([10]*3, [float('nan')]*3)]:
            with self.subTest(before=before, after=after), self.assertRaises(ValueError):
                compare.gate(before, after, absolute=5)

    def test_regression_does_not_pass(self):
        self.assertEqual(compare.gate([10]*3, [20]*3, absolute=5)['status'], 'inconclusive')

    def test_short_and_invalid_memory_captures_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.json'
            report = {'pid': 1, 'samples': [
                {'time': t, 'tree': {'errors': [], 'processes': {
                    '1:99': {'pid': 1, 'pss_bytes': 104857600}}}} for t in (0, 2)],
                'tree_summary': {'observed_lifetimes_complete': False,
                                 'pss_mib_median': {'tree': 100}}}
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, 'shorter'):
                compare.read_metric(path, 'tree')
            report['samples'][1]['time'] = 60
            report['samples'][1]['tree']['errors'] = ['read error']
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                compare.read_metric(path, 'tree')
            report['samples'][1]['tree']['errors'] = []
            path.write_text(json.dumps(report))
            # Thread turnover alone does not invalidate successfully read PSS.
            self.assertEqual(compare.read_metric(path, 'tree'), 100)
            report['samples'][1]['tree']['processes']['1:100'] = \
                report['samples'][1]['tree']['processes'].pop('1:99')
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, 'changed shell'):
                compare.read_metric(path, 'tree')


class IconInstrumentationTests(unittest.TestCase):
    def test_keeps_calllater_callback_identity_and_scan(self):
        source = (ROOT / 'config/quickshell/AppIcons.qml').read_text()
        instrumented = icons.instrument(source)
        self.assertEqual(instrumented.count('Qt.callLater(icons.rebuild)'), 1)
        self.assertEqual(instrumented.count('icons.profileRequest()'), 3)
        self.assertEqual(instrumented.count('property bool useFolderModels: true'), 1)
        body = source.split('    function rebuild() {\n')[1].split('    Instantiator {')[0]
        self.assertIn(body, instrumented)

    def test_source_drift_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'structure changed'):
            icons.instrument('Item {}')
