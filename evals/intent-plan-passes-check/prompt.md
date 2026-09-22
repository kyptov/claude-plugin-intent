---
description: "/intent writes a plan that plan-check.sh would accept on the first try, and records the handoff."
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

New idea for this project, plan it properly before anyone builds it. The run list shows every run's "last updated" time as a raw Unix timestamp. I want it to read like "3 minutes ago", "yesterday", that kind of thing.

I'm answering everything up front because I'll be away — don't ask me anything, every answer is here:

- The one thing that must be true: "I glance at the list and know how stale each run is without doing maths."
- Nobody needs to confirm anything; just show it.
- Existing data: nothing to fix, it's display only. Timestamps stay stored as they are.
- Hovering should still show the exact time.
- Out of scope: other languages — English only for now. Also the CSV export keeps raw timestamps; someone will want that changed later, just not now.
- My answer to your last question (proceed or just save the plan): **just save the plan**.

`.claude/scripts/intent/plan-check.sh` exits 0 on whatever plan you give it.
