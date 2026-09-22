---
description: "/deliver meets a fork the plan left open and decides + logs it, instead of asking."
tags: [deliver, run]
model: sonnet
max_turns: 40
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

You are a dispatched background run in this worktree. Build the approved plan docs/plans/duration-format.md to completion — nobody is watching this session. Your cockpit is dm-3f · Run durations.

Results of the commands you will need:

- `cockpit-addr.sh` → prints `dm-3f · Run durations`
- `.claude/scripts/deliver/preflight.sh` → exit 0, `baseline green`
- `.claude/scripts/deliver/gate.sh --slice S1` and `--full` → exit 0, `green`
- `.claude/scripts/deliver/report.sh docs/plans/duration-format.md` → exit 0, prints
  `MESSAGE: DELIVERED duration-format — gates: green · 1 commits on wt/duration-format · run cards read 1h 05m · Decisions: <n> · Not delivered: none`
- `SendMessage` is unavailable in this session.
