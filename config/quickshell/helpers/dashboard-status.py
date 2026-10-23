#!/usr/bin/env python3
"""Read lightweight dashboard counters; watch only while the drawer is open."""
import json
import os
from pathlib import Path
import subprocess
import sys
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


def cpu_ticks():
    try:
        # Guest times already belong to user/nice; count only the first 8 fields.
        ticks = [int(value) for value in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
        return sum(ticks), ticks[3] + ticks[4]
    except (OSError, ValueError, IndexError):
        return None


def cpu_percent(before, after):
    if before is None or after is None:
        return None
    total, idle = after[0] - before[0], after[1] - before[1]
    if total <= 0 or idle < 0:
        return None
    return max(0, min(100, (total - idle) / total * 100))


def resource_usage(before, after):
    usage = {'cpuPercent': cpu_percent(before, after)}
    try:
        memory = dict((key.rstrip(':'), int(value) * 1024)
                      for key, value, *_ in (line.split() for line in Path('/proc/meminfo').read_text().splitlines()))
        total = memory['MemTotal']
        used = max(0, total - memory['MemAvailable'])
        usage.update(memoryTotal=total, memoryUsed=used)
    except (OSError, ValueError, KeyError):
        pass
    try:
        storage = os.statvfs('/')
        usage['storageTotal'] = storage.f_blocks * storage.f_frsize
        usage['storageFree'] = storage.f_bavail * storage.f_frsize
    except OSError:
        pass
    return usage


def main():
    try:
        system = system_info()
        before = cpu_ticks()
        time.sleep(0.2)
        while True:
            after = cpu_ticks()
            print(json.dumps({'system': system, 'usage': resource_usage(before, after)}), flush=True)
            if '--watch' not in sys.argv[1:]:
                break
            before = after
            time.sleep(2)
    except (OSError, ValueError, IndexError):
        print(json.dumps({'error': 'System information unavailable'}), flush=True)


if __name__ == '__main__':
    main()
