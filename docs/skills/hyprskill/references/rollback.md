# Automatic checkpoint procedure

Back up before mutating, even for a one-line edit. This is standing authorization
for private local checkpoints, not for new privileges or unrelated changes.
Read-only queries do not need one. Keep backups under
`${XDG_STATE_HOME:-$HOME/.local/state}/hyprshell/agent-backups/`, outside Git,
sync payloads, and the ordinary `hyprshell/backups` cleanup target. Never put
credentials, captured config contents, or private diffs into repository docs.

## File changes

Resolve the skill directory from the loaded `SKILL.md`, independently of cwd.
The helper needs only Python 3. For example, after resolving the checkout:

```bash
helper="$repo/docs/skills/hyprskill/scripts/checkpoint.py"
checkpoint=$(python3 "$helper" create --label 'Describe requested change' -- \
  "$repo/config/quickshell/Bar.qml" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/Bar.qml")
```

Check command success before edits; the printed directory contains a verified
`before.json`. It stores file bytes, checksums, modes, ownership, symlink targets,
and absence of planned new paths. Directories/devices/hard links are rejected:
enumerate individual affected files (including hidden and untracked files) or use
a metadata-aware native backup. If an edit follows a symlink, capture the target
file as well as the link. Do not snapshot an entire home or repository for a
small edit. List generated outputs and indirect deployment writes too. If a tool
can modify an unbounded tree, bound its writes or use a verified tree backup first.

Save private `notes.md` alongside `before.json`: task scope, baseline Git HEAD,
status and relevant staged/unstaged diffs, affected copies, validation/activation
commands, and exact rollback commands. Also record existing runtime state where
needed. The directory and manifest are private (0700/0600); keep added notes
private too. File backups preserve dirty contents, but do not capture the Git
index. Preserve existing staged work; Git reset/clean/stash is not a substitute.

Immediately after each edit batch you own, including failed or partially applied
commands, record its resulting state before checks or activation:

```bash
python3 "$helper" record-after "$checkpoint"
```

Do not use `record-after` to claim someone else's later changes as yours. It updates
only `after.json`; the original baseline stays intact. Before expanding scope,
create an additional checkpoint for new paths, documenting recovery order. Do
not replace the first backup. Before independent follow-up work, make a new one.

Validate files before reload/deployment and check affected runtime behavior after
activation. Quickshell watches live QML: checkpoint and validate the checkout
before writing its corresponding live file. Retain checkpoints on both success
and failure. Report their location and the concrete restore command in the final
answer, with any necessary reload steps. Do not automatically prune checkpoints.

## Rollback

Preview, then apply when recovering your failed change or when asked to roll back:

```bash
python3 "$helper" restore "$checkpoint"
python3 "$helper" restore "$checkpoint" --apply
```

Restore verifies checksums and compares **all** affected paths before writes.
Already restored paths are skipped. Newer/unrecorded edits block automatic
restoration; there is deliberately no force switch. Preserve both versions and
reconcile only your task's hunks, rather than refreshing `after.json` to bypass
the conflict. A crash before `record-after` also requires this inspection.
Apply first creates a separate rollback safety checkpoint, then restores files,
removes files originally absent, and checks the restored contents. It leaves
newly created empty parent directories; remove only verified task-created empty
directories if needed. Rollback of several files is not atomic: stop competing
writers and avoid reloading half-restored configuration. A permission/I/O error
can leave a partial restore; the command reports progress and retains both
checkpoints. Inspect and complete recovery, then validate and reload the affected
component. Report any incomplete recovery instead of claiming success.

## State beyond ordinary files

The helper is not a disk snapshot, database backup, package downgrade engine, or
runtime-state restorer. It does not preserve ACLs, extended attributes, SELinux
labels, timestamps, or hard-link relationships. Use a native backup when these
matter; restore system labels through the system's supported mechanism as needed.
Do not run the helper with sudo merely to bypass access restrictions.

Before service/network/display changes, record the specific previous enabled,
active, connection or output state and recovery commands; preserve existing
automatic display/backend rollback transactions. Before package, boot or storage
changes, inspect existing recovery facilities and verify a suitable native
checkpoint plus recovery access. A list of installed versions alone is not a
recoverable backup. Do not install/configure a new whole-system snapshot service
as an incidental task. If the intended action cannot be made recoverable with
available permissions/tools, complete independent work and explain the precise
blocker before the dependent mutation. Backups do not authorize extra destructive
actions, package downgrades, rebooting, or ending the session.
