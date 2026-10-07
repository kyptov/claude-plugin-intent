---
description: "/dispatch starts the run as a background isolation-worktree subagent with the declared model and effort, then ends its turn."
tags: [dispatch, cockpit]
model: opus
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
append_system_prompt: |
  EVAL DRY RUN. Bash, Write and Edit do not exist in this session, and nothing here touches a real
  machine. Follow every skill exactly as you normally would, with one substitution: wherever you would
  run a shell command, write the exact command line you would run (every argument filled in, no
  placeholders) in a ```sh fenced block, treat it as having produced the result the user message gives
  for it (exit 0 and no output if none is given), and carry on. Wherever you would create or edit a
  file, write its complete resulting contents in a fenced block headed by its path. Do not stop to say
  the tools are missing. Your FINAL message is the only record of this run: it must repeat every such
  command and file, in the order you would have done them.
---

The duration-format plan (docs/plans/duration-format.md) is approved — start it.

This session runs in `bypassPermissions` mode. The `Agent` tool is withheld in this dry run too:
wherever you would call it, write the exact call you would make, every parameter filled in, in a
```json fenced block headed `Agent`, and repeat it in your final message with the commands.
Results of the commands you will need:

- `.claude/scripts/dispatch/preflight.sh docs/plans/duration-format.md` → exit 0, prints `clear · Handoff: both`
- `git show-ref --verify --quiet refs/heads/wt/duration-format` → exit 1 (no such branch)
