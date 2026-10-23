#!/usr/bin/env python3
"""Checkpoint and advance only verified common sync hashes for explicit task paths."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

import checkpoint


def deleted_key(relative):
    # Only used for paths already in the baseline, absent from both payloads.
    for source, target in (
        ('config/', 'config/'), ('bin/', 'home/.local/bin/'),
        ('assets/applications/', 'data/applications/'),
        ('assets/fonts/', 'data/fonts/hyprshell/'),
        ('assets/wallpapers/', 'home/Pictures/Wallpapers/'),
    ):
        if relative.startswith(source):
            return target + relative[len(source):]
    raise ValueError('Not a managed sync path: ' + relative)


def refresh(repo, paths, apply=False):
    repo = repo.resolve()
    sys.path.insert(0, str(repo / 'config/quickshell/settings'))
    import deployment
    import github_sync as sync
    from github_update import repository_lock

    if Path(sync.git(repo, 'rev-parse', '--show-toplevel')).resolve() != repo:
        raise ValueError('Choose the Hyprshell checkout root.')
    paths = list(dict.fromkeys(paths))
    if not paths or any(Path(p).is_absolute() or '..' in Path(p).parts or
                        Path(p).as_posix() != p or p == '.' for p in paths):
        raise ValueError('Use explicit repository-relative payload file paths.')
    locations = deployment.roots()
    baseline_path = locations['state'] / 'local-config-baseline.json'
    with repository_lock(repo), deployment.lock(locations):
        old = baseline_path.read_bytes() if baseline_path.exists() else None
        saved = json.loads(old) if old is not None else {'repo': str(repo), 'files': {}}
        if saved.get('repo') != str(repo) or not isinstance(saved.get('files'), dict):
            raise ValueError('Sync baseline belongs to another checkout or is invalid.')
        payload = deployment.payload(repo)
        keys = {source.relative_to(repo).as_posix(): key for key, source in payload.items()}
        selected = {}
        for relative in paths:
            if relative == 'compatibility.json':
                raise ValueError('Generated compatibility metadata is excluded from sync.')
            key = keys.get(relative)
            if key is None:
                if relative not in saved['files'] or (repo / relative).exists():
                    raise ValueError('Not a managed sync path: ' + relative)
                key = deleted_key(relative)
            live = deployment.destination(key, locations)
            deployment.safe_target(live, locations[key.split('/')[0]])
            deployment.safe_target(repo / relative, repo)
            selected[relative] = (key, live, sync.file_hash(repo / relative), sync.file_hash(live))
        with tempfile.TemporaryDirectory(prefix='hyprskill-sync-baseline-') as directory:
            candidate = Path(directory)
            for name in ('config', 'bin', 'assets', 'apps'):
                if (repo / name).exists():
                    shutil.copytree(repo / name, candidate / name, ignore=sync.copy_exclusions)
            sync.snapshot(candidate, locations['config'], locations['home'])
            captured = deployment.payload(candidate)
            updates = {}
            for relative, (key, live, current, raw_live) in selected.items():
                incoming = sync.file_hash(captured[key]) if key in captured else None
                # Require live presence as well: ancillary snapshots can retain
                # a repo fallback when the installed file is missing.
                if current != incoming or (current is None) != (raw_live is None):
                    raise ValueError('Repo and desktop differ; reconcile before completing: ' + relative)
                updates[relative] = current
        for relative, (_, live, current, raw_live) in selected.items():
            if sync.file_hash(repo / relative) != current or sync.file_hash(live) != raw_live:
                raise ValueError('Configuration changed during completion: ' + relative)
        if (baseline_path.read_bytes() if baseline_path.exists() else None) != old:
            raise ValueError('Sync baseline changed during completion.')
        changed = {p: h for p, h in updates.items() if p not in saved['files'] or saved['files'][p] != h}
        result = {'paths': paths, 'updated': sorted(changed), 'applied': False, 'checkpoint': None}
        if not apply or not changed:
            return result
        folder = checkpoint.create('Advance verified Hyprskill sync baseline', [baseline_path])
        notes = ('Task: Advance only verified common sync hashes. No payload changes.\n'
                 + 'HEAD: ' + sync.git(repo, 'rev-parse', 'HEAD') + '\n'
                 + 'Git status:\n' + sync.git(repo, 'status', '--short') + '\n'
                 + 'Paths: ' + json.dumps(paths) + '\n'
                 + 'Validation: selected repository hashes equal the actual sync snapshot; '
                 'raw source/live hashes remained stable.\n'
                 + 'Rollback: python3 ' + str(Path(checkpoint.__file__).resolve())
                 + ' restore ' + str(folder) + ' --apply\n')
        (folder / 'notes.md').write_text(notes)
        (folder / 'notes.md').chmod(0o600)
        saved['files'].update(changed)
        try:
            deployment.atomic_json(baseline_path, saved)
        finally:
            checkpoint.record_after(folder)
        result.update(applied=True, checkpoint=str(folder))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args()
    try:
        result = refresh(args.repo, args.paths, args.apply)
        print(json.dumps(result))
        if result['checkpoint']:
            print('Rollback: python3 ' + str(Path(checkpoint.__file__).resolve())
                  + ' restore ' + result['checkpoint'] + ' --apply')
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
