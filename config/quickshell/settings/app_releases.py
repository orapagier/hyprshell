"""Stage pinned desktop app releases before the deployment transaction writes files."""
import hashlib
import json
import platform
import re
import urllib.error
import urllib.request

APPS = ('hyprmatrix', 'hyprweather')
TARGETS = {'hyprmatrix': 'home/.local/bin/hyprmatrix',
           'hyprweather': 'config/quickshell/helpers/hyprweather'}
MAX_BYTES = 64 * 1024 * 1024


def version(value):
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', value):
        raise RuntimeError('Cannot determine the host glibc version: ' + value)
    return tuple(int(part) for part in value.split('.'))


def verify_binary(data, checksum):
    if hashlib.sha256(data).hexdigest() != checksum:
        raise RuntimeError('Desktop app checksum mismatch; refusing to install')
    # These release assets are little-endian, 64-bit x86 Linux ELF executables.
    if (len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01'
            or int.from_bytes(data[18:20], 'little') != 62
            or int.from_bytes(data[16:18], 'little') not in (2, 3)):
        raise RuntimeError('Desktop app release is not an x86_64 ELF executable')


def stage_apps(repo, stage, locations):
    manifest_path = repo / 'app-releases.json'
    if not manifest_path.is_file():
        if any((repo / 'apps' / (app + '-rs/Cargo.toml')).exists() for app in APPS):
            raise RuntimeError('Missing app-releases.json; cannot select desktop app binaries')
        return {}
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('format') != 1:
        raise RuntimeError('Unsupported desktop app release manifest')
    repository, tag = manifest['repository'], manifest['tag']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise RuntimeError('Invalid desktop app release repository')
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', tag):
        raise RuntimeError('Invalid desktop app release tag')
    architecture = platform.machine()
    if platform.system() != 'Linux' or architecture not in manifest['architectures']:
        raise RuntimeError('No desktop app release for this platform: ' + architecture)
    libc, libc_version = platform.libc_ver()
    if libc != 'glibc':
        raise RuntimeError('Desktop app releases require Linux with glibc')
    rows = manifest['architectures'][architecture]
    # Check all apps before downloading anything or touching the live desktop.
    for app in APPS:
        row = rows[app]
        if version(libc_version) < version(row['minimum_glibc']):
            raise RuntimeError(f"{app} requires glibc {row['minimum_glibc']} or newer; "
                               f'this machine has {libc_version}. Use a compatible release.')
        if not re.fullmatch(r'[a-f0-9]{64}', row['sha256']):
            raise RuntimeError('Invalid desktop app release checksum')
        if row['asset'] not in (app, f'{app}-linux-{architecture}'):
            raise RuntimeError('Invalid desktop app release asset name')
    staged = {}
    for app in APPS:
        row = rows[app]
        key = TARGETS[app]
        target = stage / key
        root, relative = key.split('/', 1)
        installed = locations[root] / relative
        if installed.is_file() and not installed.is_symlink():
            data = installed.read_bytes()
            if hashlib.sha256(data).hexdigest() != row['sha256']:
                data = None
        else:
            data = None
        if data is None:
            url = f"https://github.com/{repository}/releases/download/{tag}/{row['asset']}"
            request = urllib.request.Request(url, headers={'User-Agent': 'Hyprshell-installer'})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    if not response.geturl().startswith('https://'):
                        raise RuntimeError('Desktop app download redirected away from HTTPS')
                    data = response.read(MAX_BYTES + 1)
            except (OSError, urllib.error.URLError) as error:
                raise RuntimeError(f'Could not download {app}: {url}. Publish the release asset '
                                   'or check your connection, then retry. No Cargo fallback was run.') from error
            if len(data) > MAX_BYTES:
                raise RuntimeError('Desktop app release exceeds the download size limit')
        verify_binary(data, row['sha256'])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755)
        staged[key] = target
    return staged
