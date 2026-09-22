---
description: "/intent --quick on a one-line visible tweak: no interview, a committed plan, Handoff both, straight to /dispatch."
tags: [intent, cockpit]
model: opus
max_turns: 30
timeout_seconds: 900
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

/intent --quick the run card line should separate the name and the duration with " · " instead of the em-dash

This session runs under `CLAUDE_CONFIG_DIR=/Users/op/.claude-work`. Results of the commands you will need:

- `.claude/scripts/intent/plan-check.sh` → exit 0 on whatever plan you give it.
- `.claude/scripts/dispatch/preflight.sh <plan>` → exit 0, prints `clear · Handoff: both`
- `launch-run.sh` → exit 0, its last two lines are:
  ```
  WT=/Users/op/Projects/demo-wt-run-card-separator BRANCH=wt/run-card-separator SOCK=impl-demo SESSION=impl-demo-run-card-separator NAME=dm-3f · impl run-card-separator
  COCKPIT_PID=4242 SENT=yes
  ```
