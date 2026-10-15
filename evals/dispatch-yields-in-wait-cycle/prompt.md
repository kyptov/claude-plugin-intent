---
description: "Crossed blocks between two cockpits: the session whose preflight says VERDICT YIELD reports the yield and does not dispatch — and asks the operator nothing."
tags: [dispatch, cockpit, wait-cycle]
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

Start the duration-format plan (docs/plans/duration-format.md).

You are cockpit-b, session `9f3c0de0-0000-4000-8000-00000000000b`, in `bypassPermissions` mode.
Another cockpit, cockpit-a (session `4be1c0de-0000-4000-8000-00000000000a`), works in this same
repo. The `Agent` tool is withheld in this dry run too: wherever you would call it, write the exact
call you would make, every parameter filled in, in a ```json fenced block headed `Agent`, and
repeat it in your final message with the commands. Results of the commands you will need:

- `.claude/scripts/dispatch/preflight.sh docs/plans/duration-format.md` (with its `--waitfor` flag) → exit 12, prints:

  ```
  plan   docs/plans/duration-format.md (slug duration-format, trunk main)
  PASS   no land.lock
  PASS   main-checkout lease is ours (idle 2m)
  PASS   main checkout clean
  PASS   handoff: both
  OVERLAP  wt/time-canon (+1) touches this plan's files: src/duration.ts
  BLOCKED an unlanded branch touches the same files this plan will — /land it first.
  VERDICT YIELD to=4be1c0de-0000-4000-8000-00000000000a (cockpit-a) — yielded to 4be1c0de-0000-4000-8000-00000000000a (cockpit-a) to break a wait cycle: 9f3c0de0-0000-4000-8000-00000000000b (cockpit-b) -> 4be1c0de-0000-4000-8000-00000000000a (cockpit-a) -> 9f3c0de0-0000-4000-8000-00000000000b (cockpit-b)
          released: the main-checkout lease (.claude/main-checkout.lock)
          this session does not proceed: no dispatch, no landing for this target
  ```
