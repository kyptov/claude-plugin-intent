---
description: "/land files a plan's debt leftovers into the declared intake file, never into the pool file."
tags: [land, cockpit, debt]
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

[message from dm-3f · impl duration-format]
DELIVERED duration-format — gates: green · 3 commits on wt/duration-format · run cards read 1h 05m · Decisions: 1 · Not delivered: 1

(You are the cockpit dm-3f. Earlier in this session you dispatched docs/plans/duration-format.md with
`CLAUDE_CONFIG_DIR=/Users/op/.claude-work`; the run's worktree is `../demo-wt-duration-format`,
branch `wt/duration-format`. `land.sh` exits 0 and prints `LANDED 9c1e2ab feat(display): run cards show hours and minutes`.)
