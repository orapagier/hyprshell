"""Deterministic coverage for extended telemetry and optional hardware probes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('monitor_details', ROOT / 'config/quickshell/helpers/system-monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def stat(pid=42, name='example (worker)', started=123, ticks=200, rss=8):
    fields = ['0'] * 22
    fields[0], fields[11], fields[12], fields[19], fields[21] = 'S', str(ticks), '0', str(started), str(rss)
    return f'{pid} ({name}) ' + ' '.join(fields)


class DetailsTests(unittest.TestCase):
    def test_process_names_pid_reuse_and_one_thread_cpu_units(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, '42/stat', stat())
            write(root, '43/stat', stat(43, 'large process', rss=20))
            write(root, '44/stat', 'exiting process')
            first, cpu, ram = monitor.processes({}, 3, root)
            self.assertEqual(cpu, [])
            self.assertEqual(ram[0]['pid'], 43)
            self.assertEqual(first[42]['name'], 'example (worker)')
            ticks = int(3 * monitor.os.sysconf('SC_CLK_TCK') * 2)
            write(root, '42/stat', stat(ticks=200 + ticks))
            _, cpu, _ = monitor.processes(first, 3, root)
            self.assertEqual(cpu[0]['cpu'], 200)
            write(root, '42/stat', stat(started=999, ticks=999999))
            _, cpu, _ = monitor.processes(first, 3, root)
            self.assertNotIn(42, [row['pid'] for row in cpu])

    def test_core_hotplug_and_pressure_parsing(self):
        cores = monitor.cpu_cores('cpu 1 0 1 8 0\ncpu0 1 0 1 8 0\ncpu12 2 0 2 6 0\nintr 123')
        self.assertEqual(cores, {'cpu0': (10, 8), 'cpu12': (10, 6)})
        self.assertEqual(monitor.pressure('some avg10=1.25 avg60=0.2 total=9\nfull avg10=0.12 total=1'),
                         {'some': 1.25, 'full': 0.12})
        self.assertEqual(monitor.pressure('some avg10=bad'), {})

    def test_sensor_units_missing_sensors_and_zero_fan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, 'hwmon0/name', 'coretemp')
            write(root, 'hwmon0/temp1_input', '55000')
            write(root, 'hwmon0/temp1_label', 'Package id 0')
            write(root, 'hwmon0/fan1_input', '0')
            write(root, 'hwmon0/temp2_input', 'unreadable')
            temps, fans = monitor.sensors(root)
            self.assertEqual(temps, [{'name': 'coretemp · Package id 0', 'value': 55}])
            self.assertEqual(fans[0]['rpm'], 0)
            self.assertEqual(monitor.sensors(root / 'missing'), ([], []))

    def test_battery_energy_and_charge_units_and_missing_cycle_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, unit, scale in [('BAT0', 'energy', 1000000), ('BAT1', 'charge', 1000)]:
                write(root, name + '/type', 'Battery')
                write(root, name + '/' + unit + '_full', str(40 * scale))
                write(root, name + '/' + unit + '_full_design', str(50 * scale))
            write(root, 'BAT0/cycle_count', '0')
            write(root, 'BAT2/type', 'Battery')
            write(root, 'BAT2/present', '0')
            batteries = monitor.battery_details(root)
            self.assertEqual([b['unit'] for b in batteries], ['Wh', 'mAh'])
            self.assertEqual([b['full'] for b in batteries], [40, 40])
            self.assertEqual(batteries[0]['cycles'], 0)
            self.assertIsNone(batteries[1]['cycles'])

    def test_optional_commands_timeout_and_missing_tools(self):
        with patch.object(monitor.shutil, 'which', return_value=None):
            data, error = monitor.command_json(['smartctl', '-j'])
            self.assertIsNone(data)
            self.assertIn('not installed', error)
        with patch.object(monitor.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(monitor.subprocess, 'run', side_effect=subprocess.TimeoutExpired('tool', 1)):
            self.assertIn('timed out', monitor.command_json(['tool'])[1])
            self.assertEqual(monitor.wifi_link('wlan0'), {'speed': None, 'signal': None})

    def test_smart_failure_not_hidden_by_exit_status(self):
        self.assertEqual(monitor.parse_smart({'smart_status': {'passed': False}, 'temperature': {'current': 65}}),
                         {'health': 'FAILED', 'temperature': 65})
        self.assertEqual(monitor.parse_smart({'nvme_smart_health_information_log': {'critical_warning': 0}})['health'], 'Passed')
        result = subprocess.CompletedProcess([], 8, json.dumps({'smart_status': {'passed': False}}), '')
        with patch.object(monitor.shutil, 'which', return_value='/usr/bin/smartctl'), \
             patch.object(monitor.subprocess, 'run', return_value=result):
            health = monitor.smart_health(['nvme0n1'])
            self.assertEqual(health['nvme0n1']['health'], 'FAILED')
            args = monitor.subprocess.run.call_args.args[0]
            self.assertIn('standby', args)
            self.assertNotIn('-t', args)

    def test_network_addresses_and_wifi_link_without_network_requests(self):
        addresses = [{'ifname': 'wlan0', 'addr_info': [{'scope': 'global', 'local': '192.0.2.1'},
                                                      {'scope': 'link', 'local': 'fe80::1'}]},
                     {'ifname': 'lo', 'addr_info': []}]
        with patch.object(monitor, 'command_json', return_value=(addresses, '')):
            self.assertEqual(monitor.network_details(), {'wlan0': {'addresses': ['192.0.2.1']}})
        result = subprocess.CompletedProcess([], 0, 'Connected\n\tsignal: -55 dBm\n\ttx bitrate: 300.0 MBit/s\n', '')
        with patch.object(monitor.shutil, 'which', return_value='/usr/bin/iw'), \
             patch.object(monitor.subprocess, 'run', return_value=result):
            self.assertEqual(monitor.wifi_link('wlan0'), {'speed': 300, 'signal': -55})

    def test_disk_filter_excludes_partitions_and_virtual_devices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'sda/device').mkdir(parents=True)
            lines = '\n'.join('8 0 ' + name + ' 1 0 2 0 1 0 4 0 0 500 0' for name in ['sda', 'sda1', 'dm-0'])
            self.assertEqual(monitor.block_counters(lines, root), {'sda': (1024, 2048, 500)})
        text = 'header\nheader\nwlan0: 100 0 0 0 0 0 0 0 200 0\ntun0: 10 0 0 0 0 0 0 0 20 0'
        self.assertEqual(monitor.interface_counters(text), {'wlan0': (100, 200), 'tun0': (10, 20)})

    def test_gpu_amd_and_intel_fallbacks_and_nvidia_units(self):
        gpus = [dict(card='card0', driver='amdgpu', slot='0000:01:00.0', model='AMD'),
                dict(card='card1', driver='i915', slot='0000:00:02.0', model='Intel')]
        def numeric(path, scale=1):
            values = {'gpu_busy_percent': 42, 'mem_info_vram_used': 1024, 'mem_info_vram_total': 2048}
            return values.get(path.name) if 'card0' in str(path) else None
        with patch.object(monitor, 'number', side_effect=numeric):
            rows = monitor.gpu_sample(gpus)
            self.assertEqual(rows[0]['usage'], 42)
            self.assertEqual(rows[0]['memory_total'], 2048)
            self.assertIsNone(rows[1]['usage'])
            self.assertEqual(rows[1]['memory_note'], 'Shared system RAM')
        output = subprocess.CompletedProcess([], 0, '00000000:01:00.0, 70, 100, 1000, 60, 1200\n', '')
        with patch.object(monitor.shutil, 'which', return_value='/usr/bin/nvidia-smi'), \
             patch.object(monitor.subprocess, 'run', return_value=output), \
             patch.object(monitor, 'number', return_value=None):
            rows = monitor.gpu_sample([dict(gpus[0], driver='nvidia')])
            self.assertEqual(rows[0]['usage'], 70)
            self.assertEqual(rows[0]['memory_used'], 100 * 2**20)
            self.assertEqual(rows[0]['temperature'], 60)

    def test_history_is_bounded_and_slow_probes_are_not_repeated(self):
        with patch.object(monitor, 'command_json', return_value=(None, 'Unavailable')), \
             patch.object(monitor, 'gpu_identity', return_value=[]), \
             patch.object(monitor, 'processes', return_value=({}, [], [])), \
             patch.object(monitor, 'sensors', return_value=([], [])), \
             patch.object(monitor, 'smart_health', return_value={}) as health, \
             patch.object(monitor, 'network_details', return_value={}) as links:
            collector = monitor.Collector()
            for _ in range(65):
                data = collector.sample()
            self.assertTrue(all(len(values) == 60 for values in data['history'].values()))
            self.assertEqual(health.call_count, 1)
            self.assertEqual(links.call_count, 1)
            json.dumps(data, allow_nan=False)


if __name__ == '__main__':
    unittest.main()
