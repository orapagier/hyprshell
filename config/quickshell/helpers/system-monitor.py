#!/usr/bin/env python3
"""Read local kernel counters in one idle process; emit JSON every three seconds.

No shell loops, process enumeration, network requests, or privileged probes.
Slow-changing sensors/storage refresh every 30 seconds; identity is read once.
"""
import glob
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time


def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeError):
        return default


def identity():
    cpu = read('/proc/cpuinfo')
    model = next((line.split(':', 1)[1].strip() for line in cpu.splitlines()
                  if line.startswith('model name')), platform.machine())
    physical = set()
    for block in cpu.split('\n\n'):
        fields = dict(line.split(':', 1) for line in block.splitlines() if ':' in line)
        fields = {k.strip(): v.strip() for k, v in fields.items()}
        if 'physical id' in fields and 'core id' in fields:
            physical.add((fields['physical id'], fields['core id']))
    release = platform.freedesktop_os_release()
    data = dict(os=release.get('PRETTY_NAME', platform.system()), kernel=platform.release(),
                cpu_model=model, cpu_topology=f'{len(physical) or "?"} cores · {os.cpu_count()} threads',
                model=' '.join(filter(None, [read('/sys/class/dmi/id/sys_vendor'),
                                               read('/sys/class/dmi/id/product_name')])))
    # This timestamp is an estimate, never represented as a verified OS install.
    try:
        epoch = int(subprocess.check_output(['stat', '-c', '%W', '/'], text=True, timeout=2).strip())
        if 0 < epoch <= time.time():
            data['install_epoch'] = epoch
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    gpu = []
    for card in sorted(glob.glob('/sys/class/drm/card[0-9]*')):
        if not Path(card).name[4:].isdigit():
            continue
        device = Path(card) / 'device'
        vendor = read(device / 'vendor')
        name = {'0x8086': 'Intel', '0x1002': 'AMD', '0x10de': 'NVIDIA'}.get(vendor, vendor)
        driver = (device / 'driver').resolve().name if (device / 'driver').exists() else ''
        if name or driver:
            gpu.append(' '.join(filter(None, [name, driver])))
    data['gpu'] = ', '.join(gpu) or 'Unavailable'
    return data


def cpu_ticks(text):
    values = [int(n) for n in text.splitlines()[0].split()[1:9]]
    # guest counters are already included in user/nice; do not count twice.
    return sum(values), values[3] + values[4]


def cpu_percent(before, after):
    total, idle = after[0] - before[0], after[1] - before[1]
    return round(max(0, min(100, 100 * (1 - idle / total))), 1) if total > 0 else None


def memory(text):
    fields = {line.split(':')[0]: int(line.split()[1]) * 1024
              for line in text.splitlines() if ':' in line}
    return dict(memory_total=fields.get('MemTotal', 0),
                memory_available=fields.get('MemAvailable', 0),
                memory_used=max(0, fields.get('MemTotal', 0) - fields.get('MemAvailable', 0)),
                memory_cache=fields.get('Cached', 0), swap_total=fields.get('SwapTotal', 0),
                swap_used=max(0, fields.get('SwapTotal', 0) - fields.get('SwapFree', 0)))


def network():
    rx = tx = 0
    for line in read('/proc/net/dev').splitlines()[2:]:
        name, values = line.split(':', 1)
        name = name.strip()
        # Count physical links only; bridges/VPN interfaces otherwise double count.
        if not (Path('/sys/class/net') / name / 'device').exists():
            continue
        fields = values.split()
        rx += int(fields[0])
        tx += int(fields[8])
    return rx, tx


def disk_counters():
    reads = writes = 0
    for line in read('/proc/diskstats').splitlines():
        fields = line.split()
        if len(fields) < 10:
            continue
        device = Path('/sys/block') / fields[2]
        if not (device / 'device').exists():
            continue
        reads += int(fields[5]) * 512
        writes += int(fields[9]) * 512
    return reads, writes


def rate(before, after, elapsed):
    return [max(0, b - a) / elapsed for a, b in zip(before, after)] if elapsed > 0 else [0, 0]


def storage(path):
    try:
        usage = shutil.disk_usage(path)
        return f'{usage.used / 2**30:.1f} / {usage.total / 2**30:.1f} GiB · {usage.used / usage.total:.0%}'
    except OSError:
        return 'Unavailable'


class Collector:
    def __init__(self):
        self.data = identity()
        self.previous_cpu = cpu_ticks(read('/proc/stat'))
        self.previous_net = network()
        self.previous_disk = disk_counters()
        self.previous_time = time.monotonic()
        self.slow_at = -float('inf')
        # Discover sensor files once; unplugged/missing sensors remain optional.
        self.temperatures = []
        for hwmon in glob.glob('/sys/class/hwmon/hwmon*'):
            name = read(Path(hwmon) / 'name')
            for filename in glob.glob(hwmon + '/temp*_input'):
                label = read(filename.replace('_input', '_label'))
                if name in ('coretemp', 'k10temp', 'cpu_thermal'):
                    if not label or label.startswith(('Package', 'Tctl', 'Tdie')):
                        self.temperatures.append((name, filename))
        self.frequencies = glob.glob('/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq')

    def sample(self):
        now = time.monotonic()
        elapsed = now - self.previous_time
        cpu, net, disk = cpu_ticks(read('/proc/stat')), network(), disk_counters()
        rx, tx = rate(self.previous_net, net, elapsed)
        dr, dw = rate(self.previous_disk, disk, elapsed)
        self.data.update(memory(read('/proc/meminfo')))
        self.data.update(cpu_percent=cpu_percent(self.previous_cpu, cpu),
                         uptime=float(read('/proc/uptime', '0').split()[0]),
                         load=' / '.join(read('/proc/loadavg').split()[:3]),
                         tasks=read('/proc/loadavg', '0 0 0 0/0').split()[3].split('/')[-1],
                         rx_rate=rx, tx_rate=tx, rx_total=net[0], tx_total=net[1],
                         disk_read_rate=dr, disk_write_rate=dw)
        frequencies = [int(n) for p in self.frequencies if (n := read(p)).isdigit()]
        self.data['frequency'] = f'{sum(frequencies) / len(frequencies) / 1e6:.2f} GHz avg' if frequencies else 'Frequency unavailable'
        if now - self.slow_at >= 30:
            temperatures = [int(n) / 1000 for _, p in self.temperatures if (n := read(p)).lstrip('-').isdigit()]
            self.data.update(temperature=f'{max(temperatures):.0f} °C CPU' if temperatures else 'Unavailable',
                             root_usage=storage('/'), home_usage=storage(Path.home()))
            self.slow_at = now
        self.previous_cpu, self.previous_net, self.previous_disk, self.previous_time = cpu, net, disk, now
        return dict(self.data)


def main():
    collector = Collector()
    while True:
        print(json.dumps(collector.sample(), separators=(',', ':')), flush=True)
        if '--once' in sys.argv:
            return
        time.sleep(3)


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
