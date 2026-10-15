---
description: "Crossed blocks between two cockpits, older side: VERDICT WAIT runs the wait detached, and when it ends CLEAR the cockpit re-runs the preflight and dispatches — asking the operator nothing."
tags: [dispatch, cockpit, wait-cycle]
model: opus
max_turns: 30
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

Start the csv-durations plan (docs/plans/csv-durations.md).

You are cockpit-a, session `4be1c0de-0000-4000-8000-00000000000a`, in `bypassPermissions` mode.
Another cockpit, cockpit-b (session `9f3c0de0-0000-4000-8000-00000000000b`), works in this same
repo. The `Agent` tool is withheld in this dry run too: wherever you would call it, write the exact
call you would make, every parameter filled in, in a ```json fenced block headed `Agent`, and
repeat it in your final message with the commands. In this dry run a background command's completion
notification arrives at once, carrying the result given for it below; act on it in the same reply.
Results of the commands you will need, in the order they happen:

- `.claude/scripts/dispatch/preflight.sh docs/plans/csv-durations.md` (with its `--waitfor` flag), FIRST run → exit 11, prints:

  ```
  plan   docs/plans/csv-durations.md (slug csv-durations, trunk main)
  PASS   no land.lock
  BLOCKED main-checkout lease held by 9f3c0de0-0000-4000-8000-00000000000b, active 2m ago (< 45m).
  VERDICT WAIT holder=9f3c0de0-0000-4000-8000-00000000000b (cockpit-b) resource=lease — wait cycle 4be1c0de-0000-4000-8000-00000000000a (cockpit-a) -> 9f3c0de0-0000-4000-8000-00000000000b (cockpit-b) -> 4be1c0de-0000-4000-8000-00000000000a (cockpit-a); 9f3c0de0-0000-4000-8000-00000000000b (cockpit-b) yields (younger), keep waiting
  WAIT-CMD '/opt/workflow/skills/dispatch/wait-for.sh' wait --self '4be1c0de-0000-4000-8000-00000000000a' --resource 'lease' --lock '.claude/land.lock' --lease-idle 45 --trunk 'main' --max-wait 100 --lease '.claude/main-checkout.lock'
  ```

- that `WAIT-CMD`, run in the background → its completion notification: exit 0, prints
  `VERDICT CLEAR — lease is no longer held`
- the preflight, SECOND run → exit 0, prints `unlanded wt/time-canon (+1) — no overlap with this plan`, `PASS   handoff: both`, `VERDICT CLEAR`
- `git show-ref --verify --quiet refs/heads/wt/csv-durations` → exit 1 (no such branch)
