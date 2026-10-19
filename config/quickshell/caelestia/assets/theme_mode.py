#!/usr/bin/env python3
"""Select a compatible flavour before asking the official CLI to change mode."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def choose_flavour(mode, current, flavours, supported_modes, remembered=None):
    if mode in supported_modes(current["flavour"]):
        return current["flavour"]
    candidates = [remembered, *flavours]
    for flavour in dict.fromkeys(candidates):
        if flavour in flavours and mode in supported_modes(flavour):
            return flavour
    raise ValueError(
        f'{current["name"]} has no {mode} flavour. Choose another scheme or Dynamic.'
    )


def cli(*args, env=None):
    result = subprocess.run(
        ["caelestia", "scheme", *args], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Theme command failed")
    return result.stdout.strip()


def plan_mode(mode, state_root):
    current = json.loads((state_root / "caelestia/scheme.json").read_text())
    history_path = state_root / "caelestia/mode-flavours.json"
    try:
        history = json.loads(history_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        history = {}
    remembered = history.get(current["name"], {}).get(mode)
    flavours = cli("list", "-f").splitlines()

    # Query the CLI's actual mode metadata without touching the selected theme.
    with tempfile.TemporaryDirectory(prefix="sidera-theme-mode-") as temporary:
        probe = Path(temporary) / "caelestia/scheme.json"
        probe.parent.mkdir()
        environment = dict(os.environ, XDG_STATE_HOME=temporary)

        def supported_modes(flavour):
            probe.write_text(json.dumps(dict(current, flavour=flavour)))
            return cli("list", "-m", env=environment).splitlines()

        flavour = choose_flavour(mode, current, flavours, supported_modes, remembered)

    command = ["set", "--notify", "-f", flavour, "-m", mode]
    history.setdefault(current["name"], {}).update({current["mode"]: current["flavour"], mode: flavour})
    return command, history_path, history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("dark", "light"))
    parser.add_argument("--dry-run", action="store_true", help="Print the planned command without applying it")
    args = parser.parse_args()
    state_root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    try:
        command, history_path, history = plan_mode(args.mode, state_root)
        if args.dry_run:
            print(json.dumps(["caelestia", "scheme", *command]))
            return 0
        cli(*command)
        # Remember the previous dark/light flavour for the return journey.
        with tempfile.NamedTemporaryFile("w", dir=history_path.parent, delete=False) as stream:
            json.dump(history, stream)
            temporary = stream.name
        os.chmod(temporary, 0o600)
        os.replace(temporary, history_path)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
