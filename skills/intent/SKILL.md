---
name: intent
description: Phase 1 of the two-phase workflow — interview the operator to pin down what they want, decide every technical detail yourself, and write an executable plan contract (path per .claude/workflow.md) for /deliver to run unattended. Use for any new idea, feature, rough direction, "is this a good idea?", or a debt-pool item that will become implementation work. Not for executing a plan (/deliver), merging a finished worktree (/land), or questions answerable by reading code.
argument-hint: [rough idea, or a path to an existing plan/spec to turn into a contract]
---

# Interview → contract

Operator input: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: trunk branch, gate commands and their traps, plan
locations, model policy, deploy authority, canon docs. Everything project-specific comes from there,
never from assumption. If it is missing, ask the operator for the gate commands once, write the file,
then continue — never guess gates, because a wrong gate makes every downstream green meaningless.

You are the **cockpit**. This skill is the only place in the workflow where interaction happens.
Everything downstream runs unattended, so a detail you fail to pin down here becomes a decision an
autonomous cheap-model run makes on its own at 3am. Spend interaction budget here; it is free compared to
a wrong 8-hour run.

**Do not write source code in this skill. The only file you create is the plan.** That is a binding
rule here, not a mode — **do not enter plan mode** *(supersedes "Enter plan mode")*. Plan mode's only
effect on this skill was to force an `ExitPlanMode` approval dialog over a plan file the operator has
told us they do not read, on top of the one question §6 asks. Two dialogs gating one decision is one
dialog too many, so the decision lives in §6 and nowhere else.

**What replaces it as the review is §5's spoken brief.** The plan is written for an agent; the brief
is written for the operator, in the reply, in plain words. That is where a misunderstood interview
gets caught — so a thin brief is now a real failure, not a stylistic one.

---

## 1. How to interview

The operator's own workflow note: *investigate/plan = lots of interaction, implementation = none.*
Respect the split absolutely.

**Plain words, not tech words.** This is a measured, repeated request. Say "a person confirms before
it counts" — not "a human-gated state transition". Name the thing the way the operator's business
names it, not the way the schema does. If a term appears in the codebase but not in the operator's
office, it does not belong in a question.

**Ask about consequences, not implementations.** The operator decides *what the product does*; you
decide *how the code does it*. Good option text describes what changes for each kind of user the
project declaration names, and what it costs them.

**≤4 questions per round, and only questions whose answer changes what you build.** If you can resolve
it by reading code, reading `docs/`, or applying a documented convention, resolve it — silently.

**Always leave the free-text door open.** Roughly a third of this operator's answers are free-text
overrides, and those overrides regularly *add a requirement no option contained* — a safety check
before overwriting, a validation rule, "test both approaches and show me the output first". When an
answer arrives as free text, it is not a deviation from your options; **it is the requirement.**
Fold it in and, if it opens a new fork, ask one more round.

**Interview until intent is pinned, not until you have asked N questions.** Stop when you could
defend every remaining choice against the stated intent without guessing.

### What to ask about (highest yield first)

1. **The one thing that must be true when this is done** — write it down in the operator's words.
2. **Where a human must stay in the loop** vs. where the system should act alone. This operator's
   default is "do it automatically" — confirm the exceptions.
3. **What happens to data that already exists** (backfill, misreads, duplicates, hidden rows). Almost
   every feature here has a 90-day-history dimension, and it is usually where the real requirement is.
4. **What is explicitly out of scope** — the operator is good at naming this ("just leave it out of
   scope for late discussian"). Capture it verbatim; it protects the unattended run from scope creep.

## 2. Decide everything else yourself

Before writing the plan, sweep the repo conventions and settle the technical shape **without asking**:
the project's binding-rules file (named in the declaration), and only the companion docs the
declaration says apply to this area.

Never ask the operator about: table shape, file layout, naming, which package something belongs in,
library choice, error-handling pattern, migration numbering, test placement, or any question whose
answer is already written in the project's rules. Deciding these *is your job*; asking about them spends
the interaction budget that belongs to intent.

Two questions ARE worth asking even though they look technical, because they change product behaviour:
- an irreversible data action (delete / merge / overwrite rows that exist today);
- a choice that changes what a role can see (authorization, redaction) — the declaration's hard boundaries.

## 3. Write the contract

Copy the plan template to the plan location (both named in the declaration) as `<slug>.md` and fill
every section. Rules:

- **`## Your calls`** — every answer, the operator's words where they used their own.
- **`## Agent's calls`** — name each fork you are leaving to the executor **and the criterion to
  decide it by**. An empty or vague section here is the single most common cause of a 3am pause.
- **`## Canon sections`** — the exact `doc §n` anchors the executor must read, taken from the
  declaration's canon-docs list for the area; you read the whole doc during the interview so the
  cheap-model run does not have to. A plan that says "see the security doc" costs the run that whole
  doc per slice.
- **Slices** — vertical, ~2-3 files, each ending in a real repo command as its `[verify]` gate
  (the project's slicing rule). For anything larger than ~6 slices, invoke `/decompose` **if the project provides that skill** and keep
  its task file next to the plan.
- **`## Out of scope`** — mark each item `[boundary]` (excluded by design: version-deferred, another
  doc's scope) or `[gap]` (real unbuilt work someone will want). `/land` routes on that mark, filing
  the `[gap]`s into the debt pool and letting the `[boundary]`s die with the plan. An unmarked item
  gets treated as a boundary and disappears.
- **Name the debt-pool items this plan would touch.** Read the pool before writing the slices; if a
  slice would incidentally fix a listed debt, say which, so `/land` can close it. Overlap is
  invisible in both directions otherwise, and the pool's own measured problem is drain, not intake.
- **One latest version, no history.** If you revise the plan mid-interview, rewrite the section.
  Never append "changed from X to Y" — the operator has asked for this explicitly and the project's doc
  rules forbid narrating how a doc got to its current state.
- **English only**, unless the declaration says otherwise.

## 4. Where the work happens — reading in the main checkout, writing in a worktree

**Interviewing, reading and investigating: the main checkout, on the trunk.** That is what this skill
does, and it needs no isolation because it writes nothing but the plan.

**Implementing a plan: ALWAYS a worktree. There is no other option.** No plan is ever delivered in the
main checkout, however small it looks, however certain you are that nothing else is running.

Lane choice is a per-session decision while concurrency is a global property: several sessions can
each correctly observe an empty room, each choose the main checkout, and interleave their features
into one working tree. A point-in-time `git status` check cannot see a write that lands thirty minutes
later. A worktree removes the question entirely, so the answer is always the same one.

`/dispatch` creates the worktree; `/deliver` refuses to run outside one; `/land` squashes it onto the
trunk as a single commit and deletes it. Ad-hoc work the operator asks for directly in conversation —
a rename, a one-line fix, a data backfill, "is this a good idea" — is not a plan and is not this
workflow; it stays where it is.

## 5. Brief the operator in plain words

The plan is written for an agent: dense, specific, full of file paths and repo terms. **The operator
gets a different artifact — a spoken brief, in the reply itself, never written to a file.**

Its whole purpose is to check that the two of you mean the same thing *before* anything runs. Direction
drift is cheap to fix here and expensive to fix after a delivery.

How to write it:

- **Write it the way you would say it aloud** — three or four short paragraphs of continuous prose,
  the register of a phone call, so the operator hears intent rather than reads a task list.
- **Plain words. Very few technical terms** — only where no ordinary word exists, and then say what it
  means in passing. Describe what changes for the people using the product, not which module changes.
- **Short.** Three or four paragraphs is right. If it needs more, the plan is too big and should be cut
  down, not explained harder.
- Cover, in this order: what will exist and be usable when this is finished; the decisions you made on
  the operator's behalf and why; what this deliberately does not do; and what could plausibly turn out
  differently from what they expect.
- **State the one thing you are least sure they will agree with.** That sentence is the brief's real
  job. If everything reads as agreeable, you are hiding a fork.

Never restate the slice list in prose — that is a task recap and tells the operator nothing about
whether you understood them.

## 6. The last question — one question, two options, and it is the approval gate

Ask **one final `AskUserQuestion`**, directly under the brief. Its answer approves the plan *and*
authorises everything downstream; there is no second gate behind it.

**"Proceed with this, or just save the plan?"**

| Option | What you do next | Ends with |
|---|---|---|
| **Proceed — build it and land it** *(recommend this; the default answer)* | invoke `/dispatch`, which makes the worktree and starts the unattended run; `/land` squashes it onto the trunk as one commit when the gates are green | the feature landed and pushed |
| **Just save the plan** | stop here and say the plan is ready | a plan file |

**Two options, because the operator answers "both" every time** *(supersedes the four-option
"how far should I take this on my own?")*. The two that are gone are still reachable: `AskUserQuestion`
always offers free text, so "build it but leave the landing to me" or "run it while I watch" arrives
as an override — fold it in, exactly as §1 says. `## Handoff` still accepts all four values and
`/dispatch` still routes on all four; this skill has just stopped offering the two nobody picks.

Write the answer into the plan's `## Handoff` **before** you do anything else with it — `both` for
Proceed, `nothing` for Just save (the plan-check script's `--set-handoff <value>` does exactly this). That one line is the recovery path: if this turn dies, `/dispatch`
reads the answer from the file instead of asking the operator to decide twice.

**Nothing else asks for approval after this**, so nothing downstream will catch a malformed plan
either. **Run the declaration's plan-check script before you ask** — it settles, mechanically, what
§3 asks for: every section present, no template placeholder left unfilled, every slice carrying its
`- Files:` line and a `[verify]` that actually resolves in this repo, every canon `doc §n` anchor
still existing, every `## Out of scope` item marked, and no slug that already has a branch. Fix what
it reports first; a plan that fails it is a plan you are about to have authorised unread.

If the declaration names no such script, re-read the plan against that same list yourself, and tell
the operator the project should have one — `${CLAUDE_PLUGIN_ROOT}/skills/intent/BOOTSTRAP.md` builds it. This is not a
hard stop the way it is in `/deliver` §0c and `/dispatch` §1: the operator is present here, so the
check being manual is a cost, not a hazard.

## 7. Then act on the answer — in this turn, without being asked again

**This is the step that gets skipped**: a handoff answer reads like a label for a state, not an
instruction to act, so interviews end here with the plan written and nothing running.

**The answer to §6 is the approval. Act on it as your first action in that turn** — not a summary,
not a closing paragraph, not "let me know if you want me to start", and **not an `ExitPlanMode`
round**: this skill does not enter plan mode (§0), and re-asking for approval the operator just gave
is the second dialog §6 exists to remove.

| `## Handoff` | Your immediate next action |
|---|---|
| `both` | `Skill(dispatch)` — it reads `## Handoff` itself and lands when green |
| `dispatch` | `Skill(dispatch)` |
| `deliver` | `Skill(dispatch)` — the foreground variant; still a worktree |
| `nothing` | nothing. Say the plan is ready and stop. |

## 7a. Interview in parallel, then own what you dispatch

**One interview, one session, and it stays the cockpit for its own runs.** Interviews run in parallel,
one per feature, because mixing three features' interviews into one context degrades the questions —
and because the blocking resource is the operator, not the agent: median time from start to the
handoff question is 67 minutes while the agent's own work before its first question is ~2 minutes.
Serialising interviews would serialise the operator's answering. Run as many as they can answer
round-robin, about three.

**So dispatch from here; never hand the plan to another session.** `/deliver` §7 reports `DELIVERED`
to whoever dispatched it, so the session that dispatched is the session that must be alive to hear it
and the session that lands the branch. Everything else about owning a run — the watcher, which
signals mean what, and the three seams where the relay drops the baton — lives in `/dispatch` §0b,
§5 and §6, which is where you will be when it matters. It is not repeated here.
