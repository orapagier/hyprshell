#!/usr/bin/env python3
"""Read one dashboard snapshot on opening; no polling or process scans."""
import json
import os
from pathlib import Path
import subprocess
import time


def os_age_days():
    # Installer-directory birth time first; machine-id creation is a fallback.
    # Neither is a universal install date, so the UI calls this an estimate.
    now = time.time()
    for path in ("/var/log/anaconda", "/etc/machine-id"):
        try:
            result = subprocess.run(["stat", "-c", "%W", "--", path],
                                    capture_output=True, text=True, timeout=2, check=True)
            installed = int(result.stdout.strip())
            if 0 < installed <= now:
                return int((now - installed) // 86400)
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
    return None


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
    try:
        uptime = max(0, int(float(Path('/proc/uptime').read_text().split()[0])))
    except (OSError, ValueError, IndexError):
        uptime = None
    return {'uptimeSeconds': uptime, 'osAgeDays': os_age_days(), 'hostname': identity.nodename, 'os': distribution, 'kernel': identity.release, 'cpuModel': cpu,
            'memoryTotal': os.sysconf('SC_PHYS_PAGES') * os.sysconf('SC_PAGE_SIZE')}


if __name__ == '__main__':
    try:
        print(json.dumps({'system': system_info()}))
    except (OSError, ValueError, IndexError) as error:
        print(json.dumps({'error': 'System information unavailable'}))
