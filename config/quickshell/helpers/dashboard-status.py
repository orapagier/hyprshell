#!/usr/bin/env python3
"""Read static system identity once; no resource polling or process scans."""
import json
import os
from pathlib import Path


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
    return {'hostname': identity.nodename, 'os': distribution, 'kernel': identity.release, 'cpuModel': cpu,
            'memoryTotal': os.sysconf('SC_PHYS_PAGES') * os.sysconf('SC_PAGE_SIZE')}


if __name__ == '__main__':
    try:
        print(json.dumps({'system': system_info()}))
    except (OSError, ValueError, IndexError) as error:
        print(json.dumps({'error': 'System information unavailable'}))
