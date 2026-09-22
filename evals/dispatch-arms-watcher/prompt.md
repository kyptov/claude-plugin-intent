---
description: "After a launch, /dispatch starts the watcher in the SAME turn, pinned to the dispatching profile."
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

This session runs under `CLAUDE_CONFIG_DIR=/Users/op/.claude-work`. Results of the commands you will need:

- `.claude/scripts/dispatch/preflight.sh docs/plans/duration-format.md` → exit 0, prints `clear · Handoff: both`
- `launch-run.sh` → exit 0, its last two lines are:
  ```
  WT=/Users/op/Projects/demo-wt-duration-format BRANCH=wt/duration-format SOCK=impl-demo SESSION=impl-demo-duration-format NAME=dm-3f·duration-format
  COCKPIT_PID=4242 SENT=yes
  ```
- No watcher is running in this session yet.
