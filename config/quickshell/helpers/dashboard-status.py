#!/usr/bin/env python3
"""Read local resource counters on demand; no daemon or network requests."""
import json
from pathlib import Path


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
    }


if __name__ == '__main__':
    try:
        print(json.dumps(read_status()))
    except (OSError, ValueError, IndexError) as error:
        print(json.dumps({'error': 'Resource counters unavailable'}))
