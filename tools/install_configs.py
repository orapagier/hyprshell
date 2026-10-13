#!/usr/bin/env python3
"""Install/update shared files, retaining preferences unless a profile is requested."""
import argparse
from pathlib import Path
import sys
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config/quickshell/settings'))
import deployment


def install(repo, profile=None, native=False):
    fresh = not (deployment.roots()['config'] / 'hyprshell/settings.json').exists()
    result = deployment.install(repo, profile=profile, native=native)
    state = deployment.roots()['state']
    state.mkdir(parents=True, exist_ok=True)
    (state / 'repository').write_text(str(repo.resolve()) + '\n')
    # Prepare startup/default-app choices before the first UWSM login. Updating
    # shared code never reapplies associations over an existing user's choices.
    if fresh or profile:
        config = deployment.roots()['config']
        for name in ('regional', 'applications'):
            if (config / 'hyprshell' / (name + '.json')).exists():
                restored = subprocess.run(['python3', str(config / 'quickshell/settings' / (name + '.py')), '--restore'],
                                          capture_output=True, text=True, timeout=30)
                if restored.returncode:
                    print(name.capitalize() + ' preferences will be retried at login.')
    for key in result['changed']:
        print('Installed:', key)
    if not result['changed']:
        print('Unchanged: installed desktop')
    if result['backup']:
        print('Backup directory:', result['backup'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    parser.add_argument('--profile', choices=['personal'])
    parser.add_argument('--validate-native', action='store_true')
    parser.add_argument('--rollback', type=Path)
    args = parser.parse_args()
    if args.rollback:
        with deployment.lock(deployment.roots()):
            deployment.rollback(args.rollback)
    else:
        install(args.repository, args.profile, args.validate_native)


if __name__ == '__main__':
    main()
