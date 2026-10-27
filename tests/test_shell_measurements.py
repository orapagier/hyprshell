import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('measure_shell', ROOT / 'tools/measure_shell.py')
measure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measure)


class ShellMeasurementsTests(unittest.TestCase):
    def test_proc_names_and_cpu_units(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '23').mkdir()
            fields = ['0'] * 22
            fields[0] = 'S'
            fields[11], fields[12], fields[19], fields[21] = '5', '3', '99', '128'
            (root / '23/stat').write_text('23 (test ) process) ' + ' '.join(fields))
            row = measure.process_sample(23, root)
            self.assertEqual(row['ticks'], 8)
            self.assertEqual(row['start'], 99)
            self.assertEqual(row['rss_bytes'], 128 * os.sysconf('SC_PAGE_SIZE'))
        summary = measure.summarize([
            dict(row, time=0), dict(row, time=2, ticks=8 + os.sysconf('SC_CLK_TCK'))])
        self.assertEqual(summary['cpu_percent_one_core'], 50)

    def test_restart_cannot_produce_misleading_result(self):
        with self.assertRaisesRegex(ValueError, 'restarted'):
            measure.summarize([dict(start=1), dict(start=2)])
