#!/usr/bin/env python3
"""End the current graphical session through its session manager."""
import argparse
import os
import re
import shutil
import subprocess
import sys


def logout():
    if shutil.which('uwsm'):
        active = subprocess.run(['uwsm', 'check', 'is-active'], capture_output=True,
                                text=True, timeout=10)
        if active.returncode == 0:
            # UWSM stops session applications before shutting down the compositor.
            result = subprocess.run(['uwsm', 'stop'], check=False)
            if result.returncode:
                raise RuntimeError('Could not stop the UWSM session. Your session remains open.')
            return 0
        if active.returncode != 1 or (active.stderr or '').strip():
            raise RuntimeError('Could not determine the session manager. Your session remains open.')
    session = os.environ.get('XDG_SESSION_ID', '')
    if not re.fullmatch(r'[A-Za-z0-9_]+', session):
        raise RuntimeError('The current login session is unavailable. Log out through your session manager.')
    return subprocess.run(['loginctl', 'terminate-session', session], check=False).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logout', action='store_true', required=True)
    parser.parse_args()
    try:
        return logout()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
