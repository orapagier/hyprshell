#!/usr/bin/env python3
"""Package already-built desktop apps and pin their exact GitHub Release assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
from app_releases import APPS, verify_binary


def package(repo, output, tag, repository, binaries, manifest_output=None):
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', tag):
        raise ValueError('Use a simple release tag, for example v1.0.0')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Repository must be OWNER/REPO')
    rows, assets = {}, {}
    for app in APPS:
        binary = binaries[app]
        data = binary.read_bytes()
        checksum = hashlib.sha256(data).hexdigest()
        verify_binary(data, checksum)
        sources = repo / 'apps' / (app + '-rs')
        inputs = [sources / name for name in ('Cargo.toml', 'Cargo.lock')]
        inputs.extend((sources / 'src').rglob('*'))
        if any(path.is_file() and path.stat().st_mtime > binary.stat().st_mtime for path in inputs):
            raise RuntimeError(f'{app} source is newer than its binary; rebuild before packaging')
        symbols = subprocess.check_output(['readelf', '--version-info', str(binary)], text=True)
        versions = re.findall(r'GLIBC_(\d+\.\d+(?:\.\d+)?)', symbols)
        if not versions:
            raise RuntimeError('Cannot determine minimum glibc for ' + app)
        minimum = max(versions, key=lambda value: tuple(map(int, value.split('.'))))
        asset = app
        rows[app] = {'asset': asset, 'sha256': checksum, 'minimum_glibc': minimum}
        assets[asset] = data
    manifest = {'format': 1, 'repository': repository, 'tag': tag,
                'architectures': {'x86_64': rows}}
    output.mkdir(parents=True, exist_ok=True)
    for asset, data in assets.items():
        target = output / asset
        target.write_bytes(data)
        target.chmod(0o755)
    (output / 'SHA256SUMS').write_text(''.join(
        f"{rows[app]['sha256']}  {rows[app]['asset']}\n" for app in APPS))
    revision = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    (output / 'RELEASE-NOTES.md').write_text(
        f'# Hyprshell desktop apps: {tag}\n\n'
        f'Source revision: `{revision}`. Linux x86-64 release executables.\n\n'
        + ''.join(f"- {app}: glibc {rows[app]['minimum_glibc']} or newer.\n" for app in APPS)
        + '\nBuilt on Fedora 44. Fresh Arch runtime acceptance is pending. '
        'Wayland desktop runtime libraries remain supplied by Hyprshell setup.\n\n'
        'Upload both executables and SHA256SUMS as release assets, preserving their names. '
        'The installer verifies checksums pinned in app-releases.json.\n')
    (manifest_output or repo / 'app-releases.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--repository', default='orapagier/hyprshell')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest-output', type=Path,
                        help='Stage a candidate manifest without changing the installer pin')
    for app in APPS:
        parser.add_argument('--' + app, type=Path,
                            default=ROOT / 'apps' / (app + '-rs/target/release') / app)
    args = parser.parse_args()
    package(ROOT, args.output, args.tag, args.repository,
            {app: getattr(args, app) for app in APPS}, args.manifest_output)
    print('Release tag:', args.tag)
    print('Upload assets from:', args.output.resolve())
    print('Updated manifest:', args.manifest_output or ROOT / 'app-releases.json')


if __name__ == '__main__':
    main()
