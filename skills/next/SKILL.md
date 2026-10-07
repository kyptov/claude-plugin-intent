---
name: next
description: Answer "what next?" in one screen with zero task-management chores — read the commits since the last run, update and close the operator's goals from them, then rank in-flight work, goals, the roadmap's next step, the operator queue and the debt pool into at most three recommendations, each a ready-to-paste command. Also captures a goal the moment the operator states one ("task: …", "we need to …", "remember to …") into the project's goals file. Use when the operator asks what next, what to do, what is open, says they lost track, or names a task outside the plan. Not for planning one item (/intent), grooming the debt pool (/debt-review), or running operator items (/operate).
argument-hint: optional — a goal to add ("add <text>" or just the text); empty = recommend what next
---

# What next

Input: $ARGUMENTS

The operator does not manage tasks: they never open, close or re-prioritise anything. They state a
goal once, and they ask what next. Everything between — noticing a goal is done, re-ranking, knowing
what is half-built — is this skill's job, read from git and the project's ledgers.

## 0. Read the declaration

Read **`.claude/workflow.md`**. Its **Goals** section names the goals file and the local state file;
its canon-doc list names the roadmap; its debt destinations name the pool, the intake directory and
the operator queue; it names the plans directory, the kept plans and the branch namespace. If it has
no Goals section, say so and stop — guessing a path files goals where nothing reads them.

## 1. Capture mode — the operator states a goal

When `$ARGUMENTS` is a goal (with or without a leading `add`), or the operator states one in
conversation outside this skill ("task: migrate off TMS42", "we need to …", "remember to …"):

1. Read the goals file. If an existing goal already covers it, say which and change nothing.
2. Otherwise append one entry in the file's own format: the goal in the operator's words, today's
   date, the roadmap phase or plan it maps to if one obviously does, and a `Status:` line saying what
   exists now (one quick `git log --oneline -i --grep=<keyword> -10` is enough to know).
3. Commit the goals file alone (`docs` scope in the project's commit style), and confirm in one line.

No priority, no estimate, no follow-up questions. Ranking happens in §5, every time, from fresh state.
Then stop — do not run the recommendation unless the operator also asked what next.

## 2. What changed since the last run

```sh
STATE=<state file from the declaration>        # local, untracked: one line, the last trunk sha seen
LAST=$(cat "$STATE" 2>/dev/null)
git log --format='%h %cs %s' "${LAST:-HEAD@{14.days.ago}}"..HEAD   # fallback: the last 14 days
```

Read subjects, and bodies where a subject is ambiguous. This window is the only evidence §3 uses.

## 3. Goals — update, and close only on a yes

For each goal in the goals file:

- **Rewrite its `Status:` line** from the window's commits plus what the tree shows now: what exists,
  what is still open. Present tense, one line, replace the old one — never append a progress log
  (git is the record).
- **If the goal now looks done**, collect it. Ask the operator about all of them in **one**
  `AskUserQuestion` call (multi-select: each done-looking goal, with the commit that finished it).
  Delete the confirmed ones; leave the rest with their rewritten status. Never delete a goal
  without that yes — a goal is the operator's own words and closing it wrongly loses it silently.

A goal no commit touched keeps its status unchanged. Commit the goals file (alone) if anything moved.

## 4. Gather the candidates

Read only what ranking needs — never a whole multi-thousand-line ledger in the main context:

1. **In flight.** Unlanded branches in the declared namespace (`git branch --list '<ns>*'` plus
   `git log --oneline main..<branch> | wc -l`), and plans in the plans directory that are not on the
   kept list and have no branch yet (saved, never dispatched). Unfinished work outranks new work.
2. **Goals** — from the file you just updated, with any blocker its status names.
3. **The roadmap's next step** — the explicit "Next: X → Y" line in the roadmap doc, read fresh.
4. **Operator queue** — the items that block a candidate above or must happen before the next
   deploy. Count the rest; do not list them.
5. **Debt pool** — delegate: one read-only subagent on a cheap model reads the pool plus the intake
   directory and returns the two `[READY]` items that most serve the next roadmap step or an open
   goal, as `subsection + verbatim bold title + one line why`. It edits nothing.

## 5. Rank — at most three

1. **Finish before starting**: a green unlanded branch → land it; a saved plan → dispatch it.
2. **Unblock**: an operator item that blocks a goal or the roadmap's next step.
3. **Goals and the roadmap's next step**, unblocked ones only. A goal the operator stated outranks
   the roadmap's next step when they serve different things — the goal is the newer statement of
   intent. A blocked item is never recommended; it goes on the `Blocked` line with what unblocks it.
4. **One debt pull** whenever the slots allow — the project's rule is one pool item per dispatch wave,
   because a pool that only takes in work becomes a graveyard.

Each recommendation is one line of why plus one paste-ready command: `/land <branch>`,
`/dispatch <plan>`, `/operate`, or `/intent <what changes for a user, one sentence> — <source>`
where the source is the goals file + goal title, the roadmap + phase, or the pool path + subsection +
verbatim title.

## 6. Keep the pool fresh without being asked

The pool's last review date is `git log -1 --format=%cs -- <pool file>` (with an intake directory,
only `/debt-review` writes the pool). If it is more than **7 days** old, after answering start
`/debt-review` as a **background** subagent and say so in one line. Never wait for it: the operator
asked what next, not for a review. Its own report arrives when it finishes.

## 7. Answer, then record the run

Write the current `HEAD` sha to the state file. Then reply — short, nothing else:

```
Moved: <goal> → <new status>          (only goals whose status changed; "nothing moved" otherwise)
Closed: <goal>                        (only ones the operator just confirmed)

Next
1. <what> — <why now>
   <command>
2. …
3. …

Blocked: <goal or step> — waits on <x>
In the background: /debt-review (pool last reviewed <date>)
```

No table of the pool, no list of every goal, no sizes or estimates.
