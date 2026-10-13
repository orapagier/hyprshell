#!/usr/bin/env python3
"""Configure daily-driver system services without replacing existing policies."""
import argparse
import json
from datetime import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys


def invoke(arguments):
    return subprocess.run(arguments, text=True, capture_output=True, timeout=30)


def configured(unit, runner=invoke):
    # An enabled but currently stopped alternative still belongs to the user.
    for operation in ('is-enabled', 'is-active'):
        result = runner(['systemctl', operation, unit])
        if result.returncode == 0:
            return True
    return False


def checked(arguments, runner):
    result = runner(arguments)
    if result.returncode:
        raise RuntimeError('Failed: ' + ' '.join(arguments) + '\n' + result.stderr.strip())
    return result.stdout.strip()


def pam_keyring(text):
    # Optional modules cannot turn a missing keyring into a failed login.
    lines = text.splitlines()
    for kind, suffix in (('auth', ''), ('session', ' auto_start')):
        if not any(re.match(r'^-?' + kind + r'\s', line) and
                   'pam_gnome_keyring.so' in line for line in lines):
            lines.append(f'-{kind} optional pam_gnome_keyring.so{suffix}')
    return '\n'.join(lines) + '\n'


def configure(root=Path('/'), runner=invoke, policy=None):
    if policy is None:
        from system_plan import environment
        policy = {'trim': environment(root)['discard'] is True}
    checked(['systemctl', 'enable', '--now', 'cups.socket', 'avahi-daemon.service'], runner)
    if policy['trim']:
        checked(['systemctl', 'enable', '--now', 'fstrim.timer'], runner)
    else:
        print('Keeping the current trim policy: no discard support was detected.')
    alternatives = ('systemd-timesyncd.service', 'ntpd.service', 'ntp.service', 'openntpd.service')
    if any(configured(unit, runner) for unit in alternatives):
        print('Keeping the configured time synchronization service.')
    else:
        checked(['systemctl', 'enable', '--now', 'chronyd.service'], runner)
    if any(configured(unit, runner) for unit in ('ufw.service', 'nftables.service', 'iptables.service', 'ip6tables.service')):
        print('Keeping the configured firewall service and rules.')
    else:
        existing = configured('firewalld.service', runner)
        checked(['systemctl', 'enable', '--now', 'firewalld.service'], runner)
        # On a new firewall, allow LAN printer discovery. Never reset a zone,
        # remove rules, or reload an existing administrator-managed firewall.
        if not existing and not list((root / 'etc/firewalld/zones').glob('*.xml')):
            checked(['firewall-cmd', '--permanent', '--add-service=mdns'], runner)
            checked(['firewall-cmd', '--add-service=mdns'], runner)
    pam = root / 'etc/pam.d/sddm'
    if pam.is_file():
        text = pam.read_text()
        replacement = pam_keyring(text)
        if replacement != text:
            backup = root / 'var/lib/hyprshell/system-backups' / datetime.now().strftime('%Y%m%d-%H%M%S-%f') / 'sddm'
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(pam, backup)
            # Stage fully before replacement so a short write cannot truncate
            # authentication configuration. copy2 retains mode and SELinux xattrs.
            with tempfile.NamedTemporaryFile(dir=pam.parent, prefix='.hyprshell-pam-', delete=False) as stream:
                staged = Path(stream.name)
            try:
                shutil.copy2(pam, staged)
                info = pam.stat()
                os.chown(staged, info.st_uid, info.st_gid)
                with staged.open('w') as stream:
                    stream.write(replacement)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(staged, pam)
            finally:
                staged.unlink(missing_ok=True)
            print('Enabled optional SDDM keyring unlock; original PAM file backed up.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan-stdin', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Run through setup.sh, or with sudo after installing dependencies.')
    try:
        policy = None
        if args.plan_stdin:
            plan = json.load(sys.stdin)
            policy = plan['services']
            if plan.get('version') != 2 or not isinstance(policy.get('trim'), bool):
                raise ValueError('Invalid system service plan')
        configure(policy=policy)
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
