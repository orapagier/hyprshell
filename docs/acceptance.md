# Fedora fresh-install and hardware acceptance

Target: traditional Fedora Everything 44, x86_64, a normal sudo-enabled user,
working networking and the documented Hyprland COPR. Atomic systems are outside
this installer. See `compatibility.json` for the recorded desktop versions.

## Fresh VM procedure

Use a disposable Fedora Everything VM with UEFI and accelerated virtual graphics
suitable for Hyprland. Take a snapshot immediately after minimal OS installation.
Use a fresh home and no existing desktop. Never use the development laptop as a
fresh-install substitute.

1. Install Git/Python/sudo as documented in `fedora.md`, clone the candidate and
   record `git rev-parse HEAD` plus `git status --short`.
2. Run `./setup.sh --dry-run`. Check the selected repositories and login manager.
3. Run `./setup.sh`. Record completion and any errors. Reboot.
4. Log into Hyprland (uwsm-managed). Open bar menus, launcher, Settings and apps.
   Confirm an authorization prompt works.
5. Change a bar preference and shortcut. Run `./setup.sh --update`. Log out/in;
   confirm both preferences remain. A second run should have no file changes.
6. Repeat from the clean VM snapshot with `--profile personal` only when testing
   profile restoration. Verify personal settings are opt-in.
7. In a disposable checkout, exercise a previous compatible release → candidate
   update with the GitHub preview. Confirm the shown changes, missing-package
   blocking, settings preservation and rollback. Use a test repository, not a
   production branch, for synthetic failing updates.
8. Generate the local acceptance report below. Record VM completion separately
   from real hardware. Fedora container CI does not count as a VM boot test.

```bash
python3 tools/check_runtime.py --native
python3 tools/check_daily_driver.py --after-login
python3 tools/release_acceptance.py --after-login --output /tmp/hyprshell-acceptance.json
```

The generated JSON starts every manual item as `pending`. Change each to `pass`,
`fail` or `not-applicable`, adding a note for failures or unavailable hardware.
The validator rejects pending items, failures, unavailable automated checks,
unknown statuses and unexplained not-applicable items:

```bash
python3 tools/release_acceptance.py --verify /tmp/hyprshell-acceptance.json
```

## Short physical checklist

| Check | What to exercise |
| --- | --- |
| Session | Boot, login, logout, reboot and authorization prompts |
| Displays | Resolution/scaling, confirmation timeout, external display reconnect |
| Input | Keyboard layout, touchpad, brightness and media keys |
| Network | Wi-Fi reconnect and Bluetooth pairing/audio, where hardware exists |
| Sound | Speakers, microphone and wired/Bluetooth headphones |
| Lock/power | Password unlock, before-sleep lock, suspend/resume and lid behavior |
| Applications | Browser playback, default file opening and removable storage |
| Portals | Screen sharing and sandboxed app file picker |
| Update/recovery | Preferences survive update and tested rollback |

Keep local hardware reports out of profile sync. Publish only a reviewed,
redacted summary with the tested revision, environment and package versions.

## Current evidence (2026-10-13)

The development machine is Fedora 44 with Hyprland 0.56.2, Quickshell 0.3.2
(COPR Git build), UWSM 0.27.0 and detected Intel graphics. Native dependencies
pass. Isolated deployment/Git tests exercise preservation, stale previews,
conflicts and rollback. Offscreen Qt tests cover the review/apply gate.

A clean Fedora VM install and physical acceptance are **pending**. This agent
has no usable VM tooling/KVM device and cannot access desktop service/compositor
sockets. Some native Quickshell process tests also fail in this sandbox on the
unchanged baseline; these results do not certify session health.
