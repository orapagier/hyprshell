#!/usr/bin/env python3
"""Read-only, redacted hardware/package selection for Arch and Fedora."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

# PCI device families supported by iHD (Broadwell and newer). Unknown IDs are
# deliberately not inferred from the CPU: hybrid systems may have another GPU.
IHD_FAMILIES = {'16', '19', '59', '3e', '9b', '8a', '9a', '4c', '46', '45',
                '4e', '31', '5a', '56', '7d', '64', 'e2'}
I965_FAMILIES = {'00', '01', '04', '0a', '0c', '0d', '0f', '29', '2a', '2e'}
FEDORA_FIRMWARE = {
    '8086': ['iwlwifi-mvm-firmware', 'iwlwifi-dvm-firmware', 'iwlegacy-firmware', 'iwlbluetooth-firmware',
             'intel-audio-firmware', 'intel-gpu-firmware'],
    '1002': ['amd-gpu-firmware'], '10de': ['nvidia-gpu-firmware'],
    '168c': ['atheros-firmware'], '0cf3': ['atheros-firmware'],
    '14e4': ['brcmfmac-firmware'], '0a5c': ['brcmfmac-firmware'],
    '14c3': ['mt7xxx-firmware'], '0e8d': ['mt7xxx-firmware'],
    '10ec': ['realtek-firmware'], '0bda': ['realtek-firmware'],
    '1013': ['cirrus-audio-firmware'],
}
SELECTABLE = {'intel-ucode', 'amd-ucode', 'microcode_ctl', 'amd-ucode-firmware',
              'vulkan-intel', 'vulkan-radeon', 'vulkan-nouveau', 'intel-media-driver',
              'sof-firmware', 'alsa-sof-firmware'} | {
                  package for packages in FEDORA_FIRMWARE.values() for package in packages}


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def detect(root=Path('/')):
    cpu = read(root / 'proc/cpuinfo')
    vendors = sorted({vendor for vendor in ('GenuineIntel', 'AuthenticAMD') if vendor in cpu})
    pci, usb = [], []
    for device in sorted((root / 'sys/bus/pci/devices').glob('*')):
        vendor, ident, kind = (read(device / field).removeprefix('0x').lower()
                               for field in ('vendor', 'device', 'class'))
        if vendor and ident and kind:
            driver = (device / 'driver').resolve().name if (device / 'driver').is_symlink() else ''
            pci.append({'vendor': vendor, 'device': ident, 'class': kind, 'driver': driver})
    for device in (root / 'sys/bus/usb/devices').glob('*'):
        vendor = read(device / 'idVendor').lower()
        if vendor:
            usb.append(vendor)
    # No bus addresses, serials, network names or device descriptions leave here.
    return {'cpuVendors': vendors, 'pci': pci, 'usbVendors': sorted(set(usb)),
            'virtualCpu': bool(re.search(r'^flags\s*:.*\bhypervisor\b', cpu, re.MULTILINE)),
            'kernel': read(root / 'proc/sys/kernel/osrelease'),
            'battery': any(read(p / 'type') == 'Battery' for p in (root / 'sys/class/power_supply').glob('*'))}


def plan(distro, hardware, base=()):
    selected, media, notes = set(), [], []
    cpu = hardware['cpuVendors']
    if 'GenuineIntel' in cpu and not hardware.get('virtualCpu'):
        selected.add('microcode_ctl' if distro == 'fedora' else 'intel-ucode')
    if 'AuthenticAMD' in cpu and not hardware.get('virtualCpu'):
        selected.add('amd-ucode-firmware' if distro == 'fedora' else 'amd-ucode')
    if not cpu:
        notes.append('CPU vendor unavailable: microcode selection requires review.')
    if hardware.get('virtualCpu'):
        notes.append('Virtual CPU: microcode belongs to the host; no guest microcode selected.')
    pci = hardware['pci']
    gpus = [d for d in pci if d['class'].startswith('03')]
    firmware_vendors = {d['vendor'] for d in pci} | set(hardware['usbVendors'])
    if distro == 'fedora':
        for vendor in firmware_vendors:
            selected.update(FEDORA_FIRMWARE.get(vendor, []))
        if not pci and not hardware['usbVendors']:
            selected.update(p for group in FEDORA_FIRMWARE.values() for p in group)
            notes.append('Device inventory unavailable: retaining broad firmware coverage.')
    if any(d['vendor'] == '8086' and d['class'].startswith('04') for d in pci):
        selected.add('alsa-sof-firmware' if distro == 'fedora' else 'sof-firmware')
    if not gpus:
        notes.append('GPU inventory unavailable: software codecs retained; review graphics/video drivers after login.')
    for gpu in gpus:
        vendor, driver = gpu['vendor'], gpu['driver']
        if vendor == '8086':
            family = gpu['device'][:2]
            if family in IHD_FAMILIES:
                media.append('intel-media-driver')
                if distro == 'arch':
                    selected.add('vulkan-intel')
            elif family in I965_FAMILIES:
                media.append('libva-intel-driver')
                notes.append('Legacy Intel GPU: using i965; newer codecs may require software decoding.')
            else:
                notes.append('Unrecognized Intel GPU family: keep the current driver and review VA-API support.')
        elif vendor == '1002':
            if distro == 'fedora':
                media.append('mesa-va-drivers-freeworld')
            else:
                selected.add('vulkan-radeon')
            notes.append('AMD: Mesa VA-API selected; available codecs depend on GPU generation.')
        elif vendor == '10de':
            if driver == 'nouveau' and distro == 'arch':
                selected.add('vulkan-nouveau')
            notes.append('NVIDIA: preserve the existing driver; proprietary branch, Secure Boot and NVDEC/VA-API require manual review.')
        else:
            notes.append('Virtual or unrecognized GPU: retain Mesa/software decoding and review acceleration in the guest/session.')
    if distro == 'arch':
        selected.update(media)
    # Fedora's Mesa Freeworld driver replaces mesa-va-drivers. Keeping the
    # restricted package in the base plan would reinstall it on a later run.
    excluded = SELECTABLE | ({'mesa-va-drivers'} if 'mesa-va-drivers-freeworld' in media else set())
    if distro == 'fedora' and not re.search(r'\.fc\d+\b', hardware.get('kernel', '')):
        excluded |= {'kernel-modules', 'kernel-modules-extra'}
        notes.append('Fedora kernel not detected: preserve the running kernel; check custom/guest driver modules manually.')
    packages = list(dict.fromkeys([p for p in base if p not in excluded] + sorted(selected)))
    return {'version': 1, 'distribution': distro, 'cpuVendors': cpu,
            'gpuVendors': sorted({g['vendor'] for g in gpus}), 'battery': hardware['battery'],
            'packages': packages, 'mediaPackages': sorted(set(media)), 'notes': list(dict.fromkeys(notes))}


def system_preferences(result, runner=subprocess.run):
    """Keep existing codec and configured time/firewall alternatives."""
    def succeeds(arguments):
        try:
            return runner(arguments, capture_output=True, text=True, timeout=5).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False  # Inaccessible checks must not remove dependencies.

    for package, units in (
        ('chrony', ('systemd-timesyncd.service', 'ntpd.service', 'ntp.service', 'openntpd.service')),
        ('firewalld', ('ufw.service', 'nftables.service', 'iptables.service', 'ip6tables.service')),
    ):
        if any(succeeds(['systemctl', operation, unit]) for unit in units for operation in ('is-enabled', 'is-active')):
            result['packages'] = [p for p in result['packages'] if p != package]
            result['notes'].append(f'Configured alternative to {package} detected: keep it and its service policy.')
    if result['distribution'] == 'fedora' and succeeds(['rpm', '-q', 'ffmpeg']):
        result['packages'] = [p for p in result['packages'] if p != 'ffmpeg-free']
        result['notes'].append('Full FFmpeg already installed: preserve it instead of adding ffmpeg-free.')
    return result


def manifest(path):
    return [line.strip() for line in path.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--distro', required=True, choices=('arch', 'fedora'))
    parser.add_argument('--manifest', type=Path, action='append', default=[])
    parser.add_argument('--format', choices=('json', 'packages', 'media', 'summary'), default='json')
    args = parser.parse_args()
    result = plan(args.distro, detect(), [p for path in args.manifest for p in manifest(path)])
    if args.manifest:
        result = system_preferences(result)
    if args.format in ('packages', 'media'):
        print('\n'.join(result['packages' if args.format == 'packages' else 'mediaPackages']))
    elif args.format == 'summary':
        print('Hardware: CPU ' + (', '.join(result['cpuVendors']) or 'unknown') +
              '; GPU vendors ' + (', '.join(result['gpuVendors']) or 'unknown') +
              '; ' + ('laptop battery detected' if result['battery'] else 'no battery detected'))
        print('Video acceleration packages: ' + (', '.join(result['mediaPackages']) or 'none selected automatically'))
        for note in result['notes']:
            print('Review: ' + note)
    else:
        json.dump(result, sys.stdout, indent=2)
        print()


if __name__ == '__main__':
    main()
