#!/usr/bin/env python3
"""Automatically save local desktop changes without accessing the network."""
import sys

import deployment
from github_sync import save_local


def main():
    from github_update import repository
    state = deployment.roots()['state']
    try:
        committed = save_local(repository(), deployment.roots()['config'])
        deployment.atomic_json(state / 'local-save-status.json',
                               {'ok': True, 'message': 'Local changes committed.' if committed else 'Local configuration saved.'})
        return 0
    except Exception as error:
        deployment.atomic_json(state / 'local-save-status.json', {'ok': False, 'message': str(error)})
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
