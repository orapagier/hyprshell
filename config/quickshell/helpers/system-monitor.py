#!/usr/bin/env python3
"""Read local counters in one worker; emit bounded dashboard frames every 3s.

Optional tools have timeouts. Never elevate, send network probes, or start tests.
"""
import glob
from collections import deque
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


def number(path, scale=1):
    try:
        return float(read(path)) / scale
    except ValueError:
        return None


def command_json(command, timeout=1):
    """Keep optional tools from blocking collection indefinitely or printing data."""
    if not shutil.which(command[0]):
        return None, 'Tool not installed: ' + command[0]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        # smartctl uses a bitmask: nonzero can still contain valid health data.
        return json.loads(result.stdout), ''
    except subprocess.TimeoutExpired:
        return None, 'Probe timed out'
    except (OSError, ValueError):
        return None, 'Unavailable / access denied'


def cpu_cores(text):
    return {line.split()[0]: cpu_ticks(line) for line in text.splitlines()
            if line.split() and line.split()[0][3:].isdigit() and line.startswith('cpu')}


def pressure(text):
    result = {}
    for line in text.splitlines():
        fields = line.split()
        for field in fields[1:]:
            if field.startswith('avg10='):
                try:
                    result[fields[0]] = float(field.split('=', 1)[1])
                except ValueError:
                    pass
    return result


def process_stat(text, page_size):
    # comm can contain spaces and parentheses. Split after the final closing ).
    start, end = text.find('('), text.rfind(')')
    fields = text[end + 2:].split()
    if start < 0 or end < start or len(fields) < 22:
        raise ValueError('Incomplete process stat')
    return dict(name=text[start + 1:end], ticks=int(fields[11]) + int(fields[12]),
                started=int(fields[19]), rss=max(0, int(fields[21])) * page_size)


def processes(previous, elapsed, proc=Path('/proc')):
    samples, rows = {}, []
    ticks_per_second, page_size = os.sysconf('SC_CLK_TCK'), os.sysconf('SC_PAGE_SIZE')
    try:
        entries = list(proc.iterdir())
    except OSError:
        return {}, [], []
    for path in entries:
        if not path.name.isdigit():
            continue
        try:
            sample = process_stat(read(path / 'stat'), page_size)
        except (ValueError, IndexError):
            continue  # exiting/inaccessible processes are normal
        pid = int(path.name)
        old = previous.get(pid)
        cpu = None
        if old and old['started'] == sample['started'] and elapsed > 0:
            cpu = round(max(0, sample['ticks'] - old['ticks']) / ticks_per_second / elapsed * 100, 1)
        samples[pid] = sample
        rows.append(dict(pid=pid, name=sample['name'], cpu=cpu, memory=sample['rss']))
    # Only names/PIDs, never command lines or environments; 100% = one CPU thread.
    top_cpu = sorted((r for r in rows if r['cpu'] is not None), key=lambda r: r['cpu'], reverse=True)[:3]
    return samples, top_cpu, sorted(rows, key=lambda r: r['memory'], reverse=True)[:3]


def interface_counters(text):
    result = {}
    for line in text.splitlines()[2:]:
        if ':' not in line:
            continue
        name, data = line.split(':', 1)
        fields = data.split()
        if len(fields) >= 9:
            result[name.strip()] = (int(fields[0]), int(fields[8]))
    return result


def block_counters(text, sys_block=Path('/sys/block')):
    result = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 14 and (sys_block / f[2] / 'device').exists():
            result[f[2]] = (int(f[5]) * 512, int(f[9]) * 512, int(f[12]))
    return result


def sensors(hwmon=Path('/sys/class/hwmon')):
    temperatures, fans = [], []
    for chip in sorted(hwmon.glob('hwmon*')):
        name = read(chip / 'name') or chip.name
        for path in sorted(chip.glob('temp*_input')):
            value = number(path, 1000)
            if value is not None:
                temperatures.append(dict(name=name + ' · ' + (read(path.with_name(path.name.replace('_input', '_label'))) or path.name.split('_')[0]), value=value))
        for path in sorted(chip.glob('fan*_input')):
            value = number(path)
            if value is not None:
                fans.append(dict(name=name + ' · ' + (read(path.with_name(path.name.replace('_input', '_label'))) or path.name.split('_')[0]), rpm=value))
    return temperatures, fans


def throttle_counts(cpu_root=Path('/sys/devices/system/cpu')):
    # Per-core counters can be mirrored across sibling threads. Keep each one;
    # report the maximum lifetime count, not an inflated sum of mirrors.
    return {str(p): int(n) for p in cpu_root.glob('cpu[0-9]*/thermal_throttle/*_throttle_count')
            if (n := read(p)).isdigit()}


def battery_details(root=Path('/sys/class/power_supply')):
    result = []
    for path in sorted(root.iterdir()) if root.exists() else []:
        if read(path / 'type') != 'Battery' or read(path / 'present', '1') == '0':
            continue
        full, design = number(path / 'energy_full', 1e6), number(path / 'energy_full_design', 1e6)
        unit = 'Wh'
        if full is None or design is None:
            full, design = number(path / 'charge_full', 1000), number(path / 'charge_full_design', 1000)
            unit = 'mAh'
        result.append(dict(name=path.name, cycles=number(path / 'cycle_count'), full=full, design=design, unit=unit))
    return result


def parse_smart(data, error=''):
    if not data:
        return dict(health=error or 'Unavailable', temperature=None)
    status = data.get('smart_status', {}).get('passed')
    health = 'Passed' if status is True else 'FAILED' if status is False else 'Unavailable / access denied'
    nvme = data.get('nvme_smart_health_information_log', {})
    if status is None and 'critical_warning' in nvme:
        health = 'Passed' if nvme['critical_warning'] == 0 else 'NVMe warning: ' + str(nvme['critical_warning'])
    return dict(health=health, temperature=data.get('temperature', {}).get('current', nvme.get('temperature')))


def smart_health(devices):
    result = {}
    deadline = time.monotonic() + 2
    for device in devices:
        if time.monotonic() >= deadline:
            result[device] = parse_smart(None, 'Probe deferred')
            continue
        # Skip disks in standby and never start a self-test. No serials in output.
        data, error = command_json(['smartctl', '-j', '-n', 'standby', '-H', '-A', '/dev/' + device], timeout=0.7)
        result[device] = parse_smart(data, error)
    return result


def network_details():
    addresses, _ = command_json(['ip', '-j', 'address', 'show'])
    result = {}
    for entry in addresses or []:
        name = entry.get('ifname', '')
        if name == 'lo' or not name:
            continue
        result[name] = dict(addresses=[a['local'] for a in entry.get('addr_info', [])
                                      if a.get('scope') == 'global' and 'local' in a])
    return result


def wifi_link(name):
    if not shutil.which('iw'):
        return dict(speed=None, signal=None)
    try:
        result = subprocess.run(['iw', 'dev', name, 'link'], capture_output=True, text=True, timeout=0.7)
        signal, speed = None, None
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith('signal:'):
                signal = float(line.split()[1])
            if line.startswith('tx bitrate:'):
                speed = float(line.split()[2])
        return dict(speed=speed, signal=signal)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return dict(speed=None, signal=None)


def gpu_identity():
    result = []
    for card in sorted(Path('/sys/class/drm').glob('card[0-9]*')):
        if not card.name[4:].isdigit() or not (card / 'device').exists():
            continue
        device = card / 'device'
        driver = (device / 'driver').resolve().name if (device / 'driver').exists() else ''
        fields = dict(line.split('=', 1) for line in read(device / 'uevent').splitlines() if '=' in line)
        slot = fields.get('PCI_SLOT_NAME', '')
        model = read(device / 'product_name') or fields.get('PCI_ID', 'Unknown GPU')
        if slot and shutil.which('lspci'):
            try:
                output = subprocess.run(['lspci', '-s', slot], capture_output=True, text=True, timeout=0.7).stdout.strip()
                if ': ' in output:
                    model = output.split(': ', 1)[1]
            except (OSError, subprocess.TimeoutExpired):
                pass
        result.append(dict(card=card.name, model=model, driver=driver, slot=slot))
    return result


def gpu_sample(identities):
    nvidia = {}
    if any(g['driver'] == 'nvidia' for g in identities) and shutil.which('nvidia-smi'):
        try:
            query = 'pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.current.graphics'
            output = subprocess.run(['nvidia-smi', '--query-gpu=' + query, '--format=csv,noheader,nounits'],
                                    capture_output=True, text=True, timeout=1).stdout
            for line in output.splitlines():
                f = [v.strip() for v in line.split(',')]
                if len(f) == 6:
                    def numeric(v):
                        try:
                            return float(v)
                        except ValueError:
                            return None
                    nvidia[f[0].lower()[-12:]] = [numeric(v) for v in f[1:]]
        except (OSError, subprocess.TimeoutExpired):
            pass
    result = []
    for gpu in identities:
        root = Path('/sys/class/drm') / gpu['card']
        device = root / 'device'
        hwmon = device / 'hwmon'
        temperature = next((v for p in hwmon.glob('hwmon*/temp1_input') if (v := number(p, 1000)) is not None), None)
        clock = next((v for p in [root / 'gt_cur_freq_mhz', root / 'gt/gt0/rps_cur_freq_mhz', device / 'gt/gt0/rps_cur_freq_mhz']
                      if (v := number(p)) is not None), None)
        if clock is None:
            for line in read(device / 'pp_dpm_sclk').splitlines():
                if '*' in line:
                    try:
                        clock = float(line.split()[1].lower().replace('mhz', ''))
                    except (ValueError, IndexError):
                        pass
        usage, used, total = number(device / 'gpu_busy_percent'), number(device / 'mem_info_vram_used'), number(device / 'mem_info_vram_total')
        if gpu['slot'].lower() in nvidia:
            usage, used_mb, total_mb, temperature, clock = nvidia[gpu['slot'].lower()]
            used, total = used_mb * 2**20 if used_mb is not None else None, total_mb * 2**20 if total_mb is not None else None
        result.append(dict(gpu, usage=usage, memory_used=used, memory_total=total, temperature=temperature, clock=clock,
                           usage_note='Requires GPU profiling support' if gpu['driver'] in ('i915', 'xe') else 'Not exposed by driver',
                           memory_note='Shared system RAM' if gpu['driver'] in ('i915', 'xe') else 'Not exposed by driver'))
    return result


class Collector:
    def __init__(self):
        self.data = identity()
        self.previous_cpu = cpu_ticks(read('/proc/stat'))
        self.previous_net = network()
        self.previous_disk = disk_counters()
        self.previous_time = time.monotonic()
        self.slow_at = -float('inf')
        self.health_at = -float('inf')
        self.previous_cores = cpu_cores(read('/proc/stat'))
        self.previous_processes = {}
        self.previous_interfaces = interface_counters(read('/proc/net/dev'))
        self.previous_blocks = block_counters(read('/proc/diskstats'))
        self.previous_throttle = throttle_counts()
        self.gpus = gpu_identity()
        self.links = {}
        self.health = {}
        self.history = {key: deque(maxlen=60) for key in
                        ('cpu', 'memory', 'rx', 'tx', 'disk_read', 'disk_write')}
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
        cores = cpu_cores(read('/proc/stat'))
        self.data['cores'] = [dict(name=name, usage=cpu_percent(self.previous_cores[name], ticks)
                                  if name in self.previous_cores else None)
                              for name, ticks in cores.items()]
        self.previous_cores = cores
        self.previous_processes, top_cpu, top_memory = processes(self.previous_processes, elapsed)
        self.data.update(top_cpu=top_cpu, top_memory=top_memory,
                         memory_percent=round(self.data['memory_used'] / self.data['memory_total'] * 100, 1)
                         if self.data['memory_total'] else None,
                         memory_pressure=pressure(read('/proc/pressure/memory')),
                         gpus=gpu_sample(self.gpus))
        throttle = throttle_counts()
        self.data['throttle'] = dict(supported=bool(throttle),
                                     events=max(throttle.values(), default=0),
                                     recent=any(value > self.previous_throttle.get(key, value)
                                                for key, value in throttle.items()))
        self.previous_throttle = throttle
        interfaces = interface_counters(read('/proc/net/dev'))
        blocks = block_counters(read('/proc/diskstats'))
        if now - self.slow_at >= 30:
            temperatures = [int(n) / 1000 for _, p in self.temperatures if (n := read(p)).lstrip('-').isdigit()]
            self.data.update(temperature=f'{max(temperatures):.0f} °C CPU' if temperatures else 'Unavailable',
                             root_usage=storage('/'), home_usage=storage(Path.home()))
            for key, path in [('root_free', '/'), ('home_free', Path.home())]:
                try:
                    self.data[key] = shutil.disk_usage(path).free
                except OSError:
                    self.data[key] = None
            all_temperatures, fans = sensors()
            self.data.update(temperatures=all_temperatures, fans=fans, batteries=battery_details())
            self.links = network_details()
            for name in interfaces:
                if name == 'lo':
                    continue
                info = self.links.setdefault(name, dict(addresses=[]))
                root = Path('/sys/class/net') / name
                info['state'] = read(root / 'operstate', 'unknown')
                if (root / 'wireless').exists():
                    info.update(wifi_link(name))
                else:
                    speed = number(root / 'speed')
                    info.update(speed=speed if speed and speed > 0 else None, signal=None)
            self.slow_at = now
        if now - self.health_at >= 300:
            self.health = smart_health(blocks)
            self.health_at = now
        self.data['interfaces'] = []
        for name, counters in interfaces.items():
            if name == 'lo':
                continue
            received, sent = rate(self.previous_interfaces.get(name, counters), counters, elapsed)
            info = self.links.get(name, dict(addresses=[], speed=None, signal=None, state='unknown'))
            self.data['interfaces'].append(dict(info, name=name, rx=received, tx=sent,
                                                 physical=(Path('/sys/class/net') / name / 'device').exists()))
        self.data['drives'] = []
        for name, counters in blocks.items():
            old = self.previous_blocks.get(name, counters)
            received, sent = rate(old[:2], counters[:2], elapsed)
            busy = min(100, max(0, counters[2] - old[2]) / elapsed / 10) if elapsed > 0 else 0
            device = Path('/sys/block') / name / 'device'
            temp_paths = list(device.glob('hwmon/hwmon*/temp1_input')) + list(device.glob('hwmon*/temp1_input'))
            temp = next((v for p in temp_paths if (v := number(p, 1000)) is not None), None)
            health = self.health.get(name, parse_smart(None, 'Waiting for health refresh'))
            self.data['drives'].append(dict(name=name, read=received, write=sent, busy=round(busy, 1),
                                            temperature=temp if temp is not None else health['temperature'],
                                            health=health['health']))
        self.previous_interfaces, self.previous_blocks = interfaces, blocks
        values = dict(cpu=self.data['cpu_percent'], memory=self.data['memory_percent'], rx=rx, tx=tx,
                      disk_read=dr, disk_write=dw)
        for key, value in values.items():
            self.history[key].append(value)
        self.data['history'] = {key: list(values) for key, values in self.history.items()}
        self.previous_cpu, self.previous_net, self.previous_disk, self.previous_time = cpu, net, disk, now
        return dict(self.data)


def main():
    collector = Collector()
    while True:
        started = time.monotonic()
        print(json.dumps(collector.sample(), separators=(',', ':')), flush=True)
        if '--once' in sys.argv:
            return
        time.sleep(max(0, 3 - (time.monotonic() - started)))


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
