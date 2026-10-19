#!/usr/bin/env python3
"""Read local resource counters on demand; no daemon or network requests."""
import json
import os
from pathlib import Path


def read_processes(proc):
    processes = []
    page_kib = os.sysconf('SC_PAGE_SIZE') // 1024
    for entry in proc.iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            stat = (entry / 'stat').read_text()
            # comm may contain spaces and parentheses; fields after its final
            # closing parenthesis start at field 3 (state).
            end = stat.rindex(')')
            fields = stat[end + 2:].split()
            processes.append({
                'pid': int(entry.name), 'name': stat[stat.index('(') + 1:end],
                'cpuTicks': int(fields[11]) + int(fields[12]),
                'startTime': fields[19], 'memoryKiB': max(0, int(fields[21])) * page_kib,
            })
        except (OSError, ValueError, IndexError):
            # A process can exit or become inaccessible during the scan.
            continue
    return processes


def read_status(proc=Path('/proc')):
    cpu = [int(n) for n in (proc / 'stat').read_text().splitlines()[0].split()[1:9]]
    memory = {}
    for line in (proc / 'meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        memory[key] = int(value.strip().split()[0])
    total = memory.get('MemTotal', 0)
    available = memory.get('MemAvailable', memory.get('MemFree', 0))
    return {
        'cpuTotal': sum(cpu), 'cpuIdle': cpu[3] + (cpu[4] if len(cpu) > 4 else 0),
        'memoryTotal': total, 'memoryUsed': max(0, total - available),
        'uptime': float((proc / 'uptime').read_text().split()[0]),
        'processes': read_processes(proc),
        'clockTicks': os.sysconf('SC_CLK_TCK'),
    }


def system_info():
    identity = os.uname()
    try:
        release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
        distribution = release.get('PRETTY_NAME', 'Linux').strip('"')
    except OSError:
        distribution = 'Linux'
    try:
        cpu = next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name'))
    except (OSError, StopIteration):
        cpu = identity.machine
    return {'hostname': identity.nodename, 'os': distribution, 'kernel': identity.release, 'cpuModel': cpu}


if __name__ == '__main__':
    try:
        print(json.dumps(dict(read_status(), system=system_info())))
    except (OSError, ValueError, IndexError) as error:
        print(json.dumps({'error': 'Resource counters unavailable'}))
