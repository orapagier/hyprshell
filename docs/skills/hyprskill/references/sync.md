# Sync baseline completion

Sync to GitHub compares the checkout and a validated desktop snapshot against
`<state>/hyprshell/local-config-baseline.json`. Agent tasks that deploy and commit
matching copies must advance that common baseline too. Otherwise both copies can
differ from the old hash after the next manual Settings change, producing
`Repo and desktop both changed` even though the edits happened in sequence.

After validating the task and deploying its focused live changes, run the helper
with explicit repository-relative sync payload paths, including generated files
and deletions affected by the task. Use the skill's resolved directory, not cwd:

```bash
python3 <skill>/scripts/sync_baseline.py --repo <checkout> -- \
  config/hyprshell/settings.json
python3 <skill>/scripts/sync_baseline.py --repo <checkout> --apply -- \
  config/hyprshell/settings.json
```

The default previews without changing the baseline. `--apply` uses the same
repository/deployment locks and snapshot normalization as Sync to GitHub. It
checks every selected path before changing anything, checkpoints the baseline,
then advances only the selected matching hashes. It does not deploy, stage,
commit, fetch, authenticate, or push. Its checkpoint/rollback command is printed;
record it in the task's private checkpoint notes. No reload is needed.

Pass only sync payload paths, not docs/tests or unrelated files. Deleted paths
must have a prior baseline entry and be absent from both copies. Generated
compatibility metadata is excluded by sync and must not be passed.

If a selected path differs, retain both versions and reconcile only task-owned
changes. If there are pre-existing manual edits in the same file, preserve them
under the normal scope rules before establishing a common version; do not change
hashes to conceal the difference. A user preference decision is required only
when the edits cannot be reconciled without discarding existing work. If a file
changes during completion, inspect the newer edit instead of blindly retrying.

Include this step in future task checkpoints and validation plans. Restoring old
payload files also requires restoring the corresponding baseline checkpoint or
re-verifying matching copies; never reset the whole sync state. The helper prevents
stale-baseline conflicts from completed agent tasks. It intentionally retains
conflict detection for genuinely divergent repository and desktop edits.
