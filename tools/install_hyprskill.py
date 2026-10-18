#!/usr/bin/env python3
"""Link shared desktop skills and rollback commands without replacing user files."""
import argparse
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--agent', action='append', choices=['codex', 'claude', 'opencode'],
                        help='repeat to select agents; default: codex + claude + opencode')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    skills = Path(__file__).resolve().parents[1] / 'docs/skills'
    home = Path.home()
    config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    targets = {'codex': home / '.agents/skills',
               'claude': home / '.claude/skills',
               'opencode': config / 'opencode/skills'}
    selected = []
    command = skills / 'hypr-rollback/commands/hypr-rollback.md'
    for agent in dict.fromkeys(args.agent or ['codex', 'claude', 'opencode']):
        for name in ('hyprskill', 'hypr-rollback'):
            selected.append((targets[agent] / name, skills / name))
        if agent == 'codex':
            selected.append((Path(os.environ.get('CODEX_HOME') or home / '.codex') /
                             'prompts/hypr-rollback.md', command))
        elif agent == 'opencode':
            selected.append((config / 'opencode/commands/hypr-rollback.md', command))
    # Check all conflicts before making any changes. Never overwrite local skills.
    for target, source in selected:
        valid = (source / 'SKILL.md').is_file() if source.is_dir() else source.is_file()
        if not valid:
            parser.error(f'Missing skill or command: {source}')
        if os.path.lexists(target) and not (target.is_symlink() and target.resolve() == source):
            parser.error(f'Refusing to replace existing skill: {target}')
    for target, source in selected:
        if target.is_symlink():
            print(f'Already linked: {target}')
        elif args.dry_run:
            print(f'Would link: {target} -> {source}')
        else:
            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(source, target_is_directory=source.is_dir())
            except OSError as exc:
                parser.exit(1, f'Cannot install {target}: {exc}\nRun this command in your normal terminal if agent configuration is protected.\n')
            print(f'Linked: {target} -> {source}')


if __name__ == '__main__':
    main()
