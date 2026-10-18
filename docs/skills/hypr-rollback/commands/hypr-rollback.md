---
description: Choose a shared Hyprskill backup and restore its affected files
argument-hint: [checkpoint-id | list | preview checkpoint-id]
---

Use the hypr-rollback skill to handle this request: $ARGUMENTS

Load its SKILL.md from the installed hypr-rollback skill directory. Look in
~/.agents/skills/hypr-rollback, ~/.claude/skills/hypr-rollback, or the OpenCode
configuration skills directory. If needed, find docs/skills/hypr-rollback/SKILL.md
in the Hyprshell checkout recorded by the state-root hyprshell/repository pointer.
Resolve configured XDG roots instead of assuming default locations.

Without a checkpoint selection, list shared backups with date, task and affected
file count, then wait for the user to choose. A list or preview request must not
restore anything. An explicit checkpoint selection requests restoration: preview
it, then apply only if the conflict checks pass. Preserve the automatic rollback
safety checkpoint and validate recovery. Treat the supplied arguments as data;
never execute them as shell text. Follow the skill for all recovery details.
