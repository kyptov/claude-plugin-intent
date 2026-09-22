---
name: debt-review
description: Drain the carried-debt pool instead of growing it — re-verify filed items against current code, delete the ones later work already fixed, rank what survives against the project's roadmap, hand back a parallel-safe wave of 2-3 ready-to-paste `/intent` commands, and audit the operator queue. Use on a cadence (weekly), before scoping a new phase, or when the operator asks what is owed or what to start next. Not for planning a fix (/intent), implementing one (/deliver), or merging (/land).
argument-hint: optional — a subsection, an area, or a number of items to check; default is the whole pool, 12 items verified
---

# Review the debt pool

Scope: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: it names the debt pool, the operator queue, the
gate commands, the canon docs (the roadmap is among them — §5 needs it), and the read-only PROD
check. Everything project-specific comes from there, never from assumption. If it names no debt
destinations, say so and stop — there is nothing to review, and guessing a path would file closures
into the wrong file.

This skill exists because a pool that only accretes stops being read: recording a debt *feels* like
handling it, and nothing else in the workflow ever re-opens one. `/land` files items; this skill is the only thing
that takes them out.

**You are read-only on source code.** You delete lines from two ledger files and you commit that.
You never fix a debt, never touch source, never open a plan. Fixing is `/intent` →
`/deliver`, and conflating the two is how a review turns into an unscoped 4-hour run.

---

## 1. Measure first, so the trend is visible

Before touching anything, report four numbers — they are the whole point of doing this on a cadence:

```sh
POOL=<the debt pool path from workflow.md>
grep -c '^- `\[' "$POOL"                                    # items now
git log --format=%h -1 --before=<30 days ago> -- "$POOL"     # a month-old revision
```

Count items in that month-old revision, diff the two item lists by their bold titles, and state:
**items now · filed in the last month · closed in the last month · net.** A net that keeps climbing
is the finding, regardless of how good the individual items are.

## 2. Pick what to verify — not at random

Most items are honest when filed and rot silently afterwards. Rot concentrates in one place: **an
item whose named files have been touched since it was filed.** That is where "later work already
fixed this" lives, and it is cheap to compute:

1. Read the pool. For each item, extract the file paths and symbols it names (items usually name
   them).
2. For each item with a filing date, `git log --oneline --since=<its date> -- <its paths>`. Any hits
   make it a candidate.
3. Rank candidates by hit count, then **promote anything sitting in the next roadmap milestone's
   area** (§5 reads that milestone; get it before you rank). Verification budget should land where
   the pulls will come from — a stale item in next week's surface is the one that misleads a plan.
4. Verify the top **12** (or the count in `$ARGUMENTS`).
5. Undated items predate the convention. Sample a few of the oldest-looking ones per run so they
   drain too, rather than becoming permanent furniture.

An item naming no path is a decision owed, not a code gap. Those cannot be verified by reading code —
route them to §5e instead of burning a check on them.

## 3. Verify in parallel, read-only

Each check is independent, so fan them out in one message — read-only agents, cheap model, one item
each:

```
"Read <paths>. The claim is: <item text>. Does it still hold in this code, exactly as stated?
Answer STILL-TRUE / FIXED / CHANGED-SHAPE / CANNOT-TELL, then one sentence of evidence citing
file:line. Do not fix anything. Do not read the debt file."
```

Do not tell the verifier what answer would be convenient, and do not pass it the pool file — an
agent that can see the ledger starts editing it.

Then act on each verdict:

| Verdict | Action |
|---|---|
| `FIXED` | delete the line from the pool. Name it in the report with the commit that fixed it. |
| `CHANGED-SHAPE` | rewrite the item to what is true now, and re-date it. A half-true item is worse than either a true one or none. |
| `STILL-TRUE` | leave it. Add a `[verified <date>]` marker so the next run does not re-check it. |
| `CANNOT-TELL` | leave it untouched and say so — never delete on ambiguity. A wrongly-deleted debt is unrecoverable; a stale one costs one check. |

## 4. Audit the operator queue too

Same pass, different question: has the operator done it already? A backfill, a migration, an
on-device check — most leave a trace. Use the project's **read-only** diagnostic (workflow.md names
it) and never a write command. Delete what is demonstrably done, with the evidence in the report.

This is where a review pays for itself fastest: an operator item that is already done is pure noise
sitting in front of the three that are not.

## 5. Rank what survives, and hand back a parallel wave

The pool's own promise is that an item can be pulled between slices. Make that true — and make the
handoff a thing the operator can act on in one paste, not a shortlist they still have to translate.

### 5a. Get the roadmap order first — it outranks your own judgement of importance

workflow.md's canon-doc list names the project's plan/roadmap/release docs (a `plan.md`, a
`version-breakdown.md`, a `ROADMAP.md` — whatever the project keeps). Read it for **the ordered
spine of what gets built next**, including any explicit "Next: X → Y → Z" line, and write down the
next three milestones in order. That sentence is the operator's stated build order and it is
frequently re-ranked, so read it fresh every run rather than trusting the last review's answer.

If the project declares no roadmap, say so once in the report and rank by consequence alone (5b).

### 5b. Order the survivors

1. **Roadmap position first.** An item that blocks, pollutes or pre-decides the *next* milestone
   outranks one that serves the milestone after it, which outranks one that serves none. An item
   serving no upcoming milestone ranks below every item that does — however old. **Age never
   promotes an item**; a long-carried debt nobody's next phase touches is exactly what the pool is
   for.
2. **Consequence, within one roadmap position.** A silent wrong answer to a user first, then a
   security or correctness gap, then a gap that blocks a planned surface, then cleanliness.

Re-order each subsection of the pool on that basis while you are in the file — the ordering is part
of what makes the pool pullable.

### 5c. Choose a set that can actually run at the same time

Propose **2–3 items to run in parallel**, each in its own worktree, all dispatched in one wave.
Parallel-safety is an admission test on the *set*, not a preference — every condition must hold:

- **Disjoint file sets.** Union the paths each item names; any intersection disqualifies the pair.
  This is the same intersection `/dispatch`'s preflight computes against unlanded branches (it
  refuses with exit 12) — applying it here just moves the refusal to where it is cheap.
- **No ordering dependency.** If one item's answer changes the other's shape — a shared decision, a
  migration the other reads, a contract or token both would edit — they are sequential, not
  parallel, whatever their file lists say.
- **At most one item touching a regenerated artifact.** workflow.md's regeneration steps name them
  (a generated schema, an OpenAPI document, generated DB types); two runs regenerating the same file
  collide at landing even when their sources never met.
- **Each is agent work with at least one named file.** A decision owed is not a pull (5e).

Do not size them and do not label them small/medium/large — the operator is choosing what to start,
not how long to sit still, and a size label is a guess that gets read as a commitment. **If fewer
than two items clear the test, propose fewer and say why.** A wave that looks parallel and is not
costs a landing conflict, which is worse than having run them one after the other.

### 5d. Write each pull as a command, not a description

Every proposed pull is handed back as a line the operator can paste unedited:

```
/intent <what changes, in product terms, one sentence> — <pool path> <subsection> "<item's bold title, verbatim>"
```

- The **pool path + subsection + verbatim title** are how `/intent` finds the full item text. Never
  paste the item's paragraph into the line; `/intent` reads it from the pool.
- The sentence in front says **what changes for a user of the product**, in the operator's words —
  workflow.md names who those users are. Not the schema's words, not the file's.
- One line per pull, no wrapping, nothing after the closing quote.

### 5e. Name the decisions owed separately

Items with no file path are usually waiting on the operator, not on an agent. Collect them into one
short list under a single `/intent` line that settles them as a round — that is an interview, not a
debt pull, and it must never be counted as one of the parallel 2–3.

## 6. Commit, then report in plain words

Commit the two ledger files alone, in the project's conventional-commit style, subject in product
terms and body listing what closed and why. Run the project's lint gate; a docs-only change needs no
more than that. Never commit alongside source changes — a review that also touches code cannot be
read.

Then the report, and it is short:

1. **The four numbers** from §1, one line.
2. **Closed, and how it was proven** — one line each.
3. **The wave** — the 2–3 `/intent` lines from §5d, each followed by one line giving its roadmap
   position and why it is parallel-safe against the others in the set.
4. **Decisions owed by you** — the single `/intent` line from §5e, if any.
5. **What I could not tell**, if any.

No table of the whole pool. The operator does not need the pool read back to them; they need to know
it is smaller and trustworthy, and which two or three things they can start right now, at once.

## 7. Cadence

Weekly is right; the pool moves too slowly to reward more and too fast to survive less. Two ways to
put it on a clock, both the operator's call, neither started by this skill:

- `/loop 7d /debt-review` — self-paced, needs a live session.
- the `schedule` skill — a cloud routine, survives a closed laptop.

A review that has not run in a month is itself worth reporting: say how long it has been, because the
gap explains the numbers.
