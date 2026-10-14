"""Read-only compatibility evidence. Never executes code from an update preview."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess


def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=20)
        return result.stdout.strip() if result.returncode == 0 else ''
    except (OSError, subprocess.SubprocessError):
        return ''


def version(text):
    match = re.search(r'(?<!\d)(\d+)\.(\d+)\.(\d+)', text)
    return tuple(map(int, match.groups())) if match else None


def machine():
    osinfo = {}
    for line in Path('/etc/os-release').read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep:
            osinfo[key] = value.strip('"')
    versions = {}
    for name, args in {'hyprland': ['Hyprland', '--version-json'],
                       'quickshell': [shutil.which('quickshell') or 'qs', '--version'],
                       'uwsm': ['uwsm', '--version']}.items():
        output = command(args)
        if name == 'hyprland':
            try:
                output = json.loads(output)['version']
            except (ValueError, KeyError, TypeError):
                output = ''
        parsed = version(output)
        versions[name] = '.'.join(map(str, parsed)) if parsed else 'unknown'
    # Query the host's Qt 6 base package, not an unqualified Qt 5 tool or SDK.
    distro = osinfo.get('ID', 'unknown')
    qt = command(['rpm', '-q', '--qf', '%{VERSION}', 'qt6-qtbase']) if distro == 'fedora' else (
        command(['pacman', '-Q', 'qt6-base']) if distro == 'arch' else '')
    parsed = version(qt)
    versions['qt6'] = '.'.join(map(str, parsed)) if parsed else 'unknown'
    vendors = set()
    for device in Path('/sys/class/drm').glob('card[0-9]*/device/vendor'):
        try:
            vendors.add({'0x8086': 'Intel', '0x1002': 'AMD', '0x10de': 'NVIDIA'}.get(device.read_text().strip(), 'Other'))
        except OSError:
            pass
    return {'distribution': osinfo.get('ID', 'unknown'), 'release': osinfo.get('VERSION_ID', 'rolling'),
            'architecture': platform.machine(), 'versions': versions, 'graphics': sorted(vendors),
            'atomic': Path('/run/ostree-booted').exists()}


def packages(path):
    if not path.is_file():
        return []
    result = []
    for line in path.read_text().splitlines():
        item = line.split('#', 1)[0].strip()
        if item:
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.+:/@()-]*', item):
                raise ValueError('Invalid package name in update manifest')
            result.append(item)
    return sorted(set(result))


def missing_packages(names, distro):
    missing = []
    for name in names:
        args = ['rpm', '-q', '--whatprovides', name] if distro == 'fedora' else ['pacman', '-T', name]
        try:
            result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            if result.returncode:
                missing.append(name)
        except (OSError, subprocess.SubprocessError):
            missing.append(name)
    return missing


def assess(manifest, info=None, package_names=None):
    info = info or machine()
    blockers, warnings, checks = [], [], []
    if manifest.get('format') not in (1, 2):
        raise ValueError('This update requires a newer compatibility checker.')
    if info['atomic']:
        blockers.append('Fedora Atomic/OSTree is not supported by this installer.')
    if info['architecture'] not in manifest['architectures']:
        blockers.append('Unsupported processor architecture: ' + info['architecture'])
    else:
        checks.append('Processor architecture: ' + info['architecture'])
    releases = manifest['distributions'].get(info['distribution'], [])
    if not releases or info['release'] not in releases and 'rolling' not in releases:
        blockers.append('Unsupported operating system: ' + info['distribution'] + ' ' + info['release'])
    else:
        checks.append('Operating system: ' + info['distribution'] + ' ' + info['release'])
    evidence = manifest.get('platform_evidence', {}).get(info['distribution'], {})
    tested = evidence.get('versions', manifest['tested'])
    for name in sorted(manifest['minimum'].keys() | manifest.get('required_major', {}).keys()):
        required = manifest['minimum'].get(name)
        current = info['versions'].get(name, 'unknown')
        parsed, minimum = version(current), version(required) if required else None
        if required and minimum is None:
            raise ValueError('Invalid minimum version')
        major = manifest.get('required_major', {}).get(name)
        excluded = manifest.get('incompatible', {}).get(name, {})
        if parsed is None or minimum and parsed < minimum or major is not None and parsed[0] != major:
            requirement = required + '+' if required else f'major version {major}'
            blockers.append(f'{name}: {requirement} required; installed {current}.')
        elif current in excluded:
            blockers.append(f'{name} {current} is incompatible: {excluded[current]}')
        elif current not in tested.get(name, []):
            warnings.append(f'{name} {current} meets the requirements but has not been recorded as tested for this distribution.')
        else:
            checks.append(f'{name} {current}: recorded baseline version for this distribution.')
    if evidence.get('last_working_date'):
        checks.append('Last reported working desktop: ' + evidence['last_working_date'] + '. ' + evidence.get('basis', ''))
    warnings.extend(evidence.get('notes', []))
    missing = missing_packages(package_names or [], info['distribution'])
    if missing:
        blockers.append('Install required packages using your system package manager, then check again: ' + ', '.join(missing))
    graphics = ', '.join(info['graphics']) or 'not accessible'
    checks.append('Detected graphics: ' + graphics)
    if 'NVIDIA' in info['graphics']:
        warnings.append('NVIDIA detected: driver/compositor compatibility, Secure Boot and resume need a physical test.')
    warnings.append('Hardware behavior is not certified by these checks. Verify login, displays, audio, lock/suspend and screen sharing after updating.')
    return {'compatible': not blockers, 'blockers': blockers, 'warnings': warnings,
            'checks': checks, 'machine': info, 'missingPackages': missing,
            'acceptance': manifest.get('acceptance', 'No acceptance record supplied.')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--platform-only', action='store_true', help='Check OS and architecture before package installation')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.platform_only:
        manifest.update(minimum={}, required_major={}, incompatible={})
    result = assess(manifest)
    if args.json:
        print(json.dumps(result))
    else:
        for name in ('checks', 'warnings', 'blockers'):
            for item in result[name]:
                print(name.upper() + ': ' + item)
    return 0 if result['compatible'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
