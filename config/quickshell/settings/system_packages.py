"""Distribution-specific package operations shared by Settings helpers."""
from pathlib import Path
import shlex


def distribution():
    values = {}
    for line in Path('/etc/os-release').read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            parts = shlex.split(value)
            values[key] = parts[0] if len(parts) == 1 else ''
    name = values.get('ID', '')
    if name not in ('arch', 'fedora'):
        raise ValueError('Package operations support Arch Linux and Fedora.')
    return name


def upgrade_command():
    return ['sudo', 'dnf', 'upgrade', '--refresh'] if distribution() == 'fedora' else ['sudo', 'pacman', '-Syu']


def install_command(packages, *, distro=None):
    distro = distribution() if distro is None else distro
    if distro not in ('arch', 'fedora'):
        raise ValueError('Package operations support Arch Linux and Fedora.')
    if distro == 'fedora':
        aliases = {'github-cli': 'gh', 'sane': 'sane-backends'}
        return ['sudo', 'dnf', 'install', *[aliases.get(name, name) for name in packages]]
    return ['sudo', 'pacman', '-Syu', '--needed', *packages]


def metadata():
    if distribution() == 'fedora':
        return {'name': 'Fedora', 'news': 'https://fedoramagazine.org/',
                'help': 'https://docs.fedoraproject.org/en-US/quick-docs/dnf/',
                'foreign': 'Review enabled COPR repositories before Fedora release upgrades.',
                'log': '/var/log/dnf5.log'}
    return {'name': 'Arch', 'news': 'https://archlinux.org/news/',
            'help': 'https://wiki.archlinux.org/title/System_maintenance#Upgrading_the_system',
            'foreign': 'AUR and other foreign packages need separate review after the full upgrade.',
            'log': '/var/log/pacman.log'}
