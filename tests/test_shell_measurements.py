import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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

    def test_capture_duration_excludes_initial_collection_delay(self):
        with patch.object(measure.time, 'monotonic', side_effect=[0, 0.02, 1.015, 1.025]), \
                patch.object(measure.time, 'sleep'), \
                patch.object(measure, 'process_sample', side_effect=[{}, {}, {}]), \
                patch.object(measure, 'tree_sample', return_value={}):
            samples = measure.collect_samples(42, 1)
        self.assertEqual(len(samples), 3)
        self.assertGreaterEqual(samples[-1]['time'] - samples[0]['time'], 1)


class ProcessTreeTests(unittest.TestCase):
    def make_process(self, root, pid, ppid=0, start=100, tids=None):
        path = root / str(pid)
        path.mkdir(exist_ok=True)
        fields = ['0'] * 22
        fields[0], fields[1], fields[19] = 'S', str(ppid), str(start)
        fields[11] = '10'
        raw = f'{pid} (test ) worker) ' + ' '.join(fields)
        (path / 'stat').write_text(raw)
        (path / 'smaps_rollup').write_text('Pss: 1024 kB\n')
        (path / 'fd').mkdir(exist_ok=True)
        (path / 'fd/0').touch()
        for tid in tids or [pid]:
            task = path / 'task' / str(tid)
            task.mkdir(parents=True, exist_ok=True)
            (task / 'stat').write_text(raw)
            (task / 'status').write_text('Name: worker\nvoluntary_ctxt_switches: 10\nnonvoluntary_ctxt_switches: 2\n')
            (task / 'schedstat').write_text('100 200 3\n')
        return path

    def sample(self, root, time):
        return dict(time=time, tree=measure.tree_sample(1, root))

    def test_recursive_tree_and_all_thread_deltas(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_process(root, 1, tids=[1, 10])
            self.make_process(root, 2, ppid=1)
            self.make_process(root, 3, ppid=2)
            self.make_process(root, 4)  # unrelated process must be excluded
            before = self.sample(root, 0)
            self.assertEqual(before['tree']['processes']['1:100']['threads']['1:100']['name'], 'worker')
            (root / '1/task/10/status').write_text('voluntary_ctxt_switches: 15\nnonvoluntary_ctxt_switches: 4\n')
            (root / '1/task/10/schedstat').write_text('150 270 6\n')
            after = self.sample(root, 2)
            result = measure.summarize_tree([before, after], 1)
            self.assertEqual(result['pss_mib_median'], {'shell': 1, 'helpers': 2, 'tree': 3})
            self.assertEqual(result['tree_counts']['threads'], {'min': 4, 'max': 4})
            self.assertEqual(result['tree_counts']['fds'], {'min': 3, 'max': 3})
            self.assertEqual(result['scheduling_deltas']['voluntary_ctxt_switches'], 5)
            self.assertEqual(result['scheduling_deltas']['runqueue_wait_ns'], 70)
            self.assertEqual(result['scheduling_deltas']['timeslices'], 3)
            self.assertTrue(result['observed_lifetimes_complete'])

    def test_pid_reuse_and_thread_churn_are_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_process(root, 1)
            self.make_process(root, 2, ppid=1)
            before = self.sample(root, 0)
            self.make_process(root, 2, ppid=1, start=200)
            self.make_process(root, 1, tids=[1, 10])
            result = measure.summarize_tree([before, self.sample(root, 2)], 1)
            self.assertFalse(result['observed_lifetimes_complete'])
            self.assertTrue(result['memory_snapshots_complete'])
            self.assertEqual(result['processes_created'], ['2:200'])
            self.assertEqual(result['processes_exited'], ['2:100'])
            self.assertIn('1:100/10:100', result['threads_created'])
            self.assertEqual(result['observed_cpu_percent_one_core'], 0)

    def test_missing_pss_is_not_zero_and_schedstat_is_optional(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = self.make_process(root, 1)
            (path / 'smaps_rollup').unlink()
            (path / 'task/1/schedstat').unlink()
            samples = [self.sample(root, 0), self.sample(root, 2)]
            result = measure.summarize_tree(samples, 1)
            self.assertIsNone(result['pss_mib_median']['tree'])
            self.assertIsNone(result['scheduling_deltas']['runtime_ns'])
            self.assertFalse(result['observed_lifetimes_complete'])
            self.assertTrue(samples[0]['tree']['errors'])

    def test_missing_thread_counters_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = self.make_process(root, 1)
            (path / 'task/1/status').write_text('Name: worker\n')
            self.assertTrue(measure.tree_sample(1, root)['errors'])

    def test_memory_attribution_and_helper_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_process(root, 1)
            child = self.make_process(root, 2, ppid=1)
            (child / 'comm').write_text('python3\n')
            (child / 'smaps_rollup').write_text('Pss: 2048 kB\nPss_Anon: 1024 kB\nPss_File: 1024 kB\nPrivate_Dirty: 100 kB\n')
            samples = [self.sample(root, 0), self.sample(root, 2)]
            row = samples[0]['tree']['processes']['2:100']
            self.assertEqual(row['memory_bytes']['Pss_Anon'], 1048576)
            self.assertNotIn('Pss_Shmem', row['memory_bytes'])
            summary = measure.summarize_tree(samples, 1)['process_pss']['2:100']
            self.assertEqual(summary['role'], 'helper')
            self.assertEqual(summary['name'], 'python3')
            self.assertEqual(summary['pss_mib_median'], 2)
