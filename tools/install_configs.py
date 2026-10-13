#!/usr/bin/env python3
"""Install/update shared files, retaining preferences from a single canonical configuration."""
import argparse
import os
import pwd
from pathlib import Path
import sys
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config/quickshell/settings'))
import deployment


def install(repo, native=False):
    fresh = not (deployment.roots()['config'] / 'hyprshell/settings.json').exists()
    result = deployment.install(repo, native=native)
    state = deployment.roots()['state']
    state.mkdir(parents=True, exist_ok=True)
    (state / 'repository').write_text(str(repo.resolve()) + '\n')
    # Prepare startup/default-app choices before the first UWSM login. Updating
    # shared code never reapplies associations over an existing user's choices.
    if fresh:
        config = deployment.roots()['config']
        for name in ('regional', 'applications'):
            if (config / 'hyprshell' / (name + '.json')).exists():
                restored = subprocess.run(['python3', str(config / 'quickshell/settings' / (name + '.py')), '--restore'],
                                          capture_output=True, text=True, timeout=30)
                if restored.returncode:
                    print(name.capitalize() + ' preferences will be retried at login.')
    units = deployment.roots()['config'] / 'systemd/user'
    timer = units / 'hyprshell-local-save.timer'
    if timer.exists():
        wants = units / 'timers.target.wants'
        wants.mkdir(parents=True, exist_ok=True)
        link = wants / timer.name
        if not link.exists():
            link.symlink_to('../' + timer.name)
        # Setup in an isolated home must not start a service in the host session.
        if (Path.home() == Path(pwd.getpwuid(os.getuid()).pw_dir)
                and os.environ.get('XDG_RUNTIME_DIR') == '/run/user/' + str(os.getuid())):
            subprocess.run(['systemctl', '--user', 'daemon-reload'], capture_output=True, timeout=15)
            enabled = subprocess.run(['systemctl', '--user', 'start', timer.name], capture_output=True, timeout=15)
            if enabled.returncode:
                print('Local automatic saving will start at the next login.')
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
    parser.add_argument('--validate-native', action='store_true')
    parser.add_argument('--rollback', type=Path)
    args = parser.parse_args()
    if args.rollback:
        with deployment.lock(deployment.roots()):
            deployment.rollback(args.rollback)
    else:
        install(args.repository, args.validate_native)


if __name__ == '__main__':
    main()
