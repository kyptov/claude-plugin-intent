---
name: intent
description: Phase 1 of the two-phase workflow — interview the operator to pin down what they want, decide every technical detail yourself, and write an executable plan contract (path per .claude/workflow.md) for /deliver to run unattended. Use for any new idea, feature, rough direction, "is this a good idea?", or a debt-pool item that will become implementation work; `--quick` skips the interview for a small visible tweak. Not for executing a plan (/deliver), merging a finished worktree (/land), or questions answerable by reading code.
argument-hint: [--quick] [rough idea, or a path to an existing plan/spec to turn into a contract]
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
rule here, not a mode — **do not enter plan mode**. The operator does not read the plan file, and the
one approval lives in §6 and nowhere else.

**The review is §5's spoken brief.** The plan is written for an agent; the brief is written for the
operator, in the reply, in plain words. That is where a misunderstood interview gets caught — so a
thin brief is a real failure, not a stylistic one.

## 0a. `--quick` — the lane for small, visible tweaks

When `$ARGUMENTS` starts with `--quick`, the operator is saying: *this is small, I have said all
there is to say, build it.* Typical asks: "fix shadow clipping (left side)", "buttons should stay to
the right when load opens".

**First decide whether it qualifies — by reading the code, not by asking.** It does only if all hold:

- the change is visible behaviour or presentation in one area — layout, styling, copy, a control's
  placement or default, a small client-side rule;
- one slice, roughly three files, in one package;
- no schema or migration, no API route or contract, no change to what a role can see, no action on
  data that exists today, no new dependency.

**If it does not qualify, say so in one sentence, naming the rule it breaks, and run the normal
interview from §1.** Never quietly shrink a real feature to fit the lane.

**If it qualifies, the rest of this skill changes in four places:**

1. **No interview (§1).** Resolve an ambiguity by picking the reading that matches how the product
   already does the same thing elsewhere — "same as the other screen" is usually implicit — and
   record each such pick under `## Agent's calls` with what it was chosen over.
2. **§3 is unchanged in form.** The full template, every section, and the plan-check script must pass;
   the plan is just short — one slice, the operator's words verbatim under `## Your calls`, and only
   the canon anchors that actually cover the touched files.
3. **§5's brief shrinks to one or two sentences:** what will look or act differently, and the one
   call you made that they might not have.
4. **§6 asks nothing: `--quick` is the approval.** Set `## Handoff` to `both`, commit the plan (§6),
   and invoke `/dispatch` in the same turn — the brief goes in that same reply. The one exception: if
   reading the code turned up two plausible readings that would *look* different to the user, ask a
   single question that offers both readings as its options; the answer is the approval.

---

## 1. How to interview

The split: *investigate/plan = lots of interaction, implementation = none.*
Respect the split absolutely.

**Plain words, not tech words.** Say "a person confirms before it counts" — not "a human-gated state
transition". Name the thing the way the operator's business names it, not the way the schema does. If
a term appears in the codebase but not in the operator's office, it does not belong in a question.

**Ask about consequences, not implementations.** The operator decides *what the product does*; you
decide *how the code does it*. Good option text describes what changes for each kind of user the
project declaration names, and what it costs them.

**≤4 questions per round, and only questions whose answer changes what you build.** If you can resolve
it by reading code, reading `docs/`, or applying a documented convention, resolve it — silently.

**Always leave the free-text door open.** Free-text answers regularly *add a requirement no option
contained* — a safety check
before overwriting, a validation rule, "test both approaches and show me the output first". When an
answer arrives as free text, it is not a deviation from your options; **it is the requirement.**
Fold it in and, if it opens a new fork, ask one more round.

**Interview until intent is pinned, not until you have asked N questions.** Stop when you could
defend every remaining choice against the stated intent without guessing.

### What to ask about (highest yield first)

1. **The one thing that must be true when this is done** — write it down in the operator's words.
2. **Where a human must stay in the loop** vs. where the system should act alone. Default to "do it
   automatically" and confirm the exceptions.
3. **What happens to data that already exists** (backfill, misreads, duplicates, hidden rows). Most
   features touch existing data somewhere, and that is usually where the real requirement is.
4. **What is explicitly out of scope** — operators usually name this readily. Capture it verbatim; it
   protects the unattended run from scope creep.

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
  invisible in both directions otherwise, and the pool's problem is drain, not intake.
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

**Offer only these two.** `AskUserQuestion` always offers free text, so "build it but leave the
landing to me" (`dispatch`) or "run it while I watch" (`deliver`) arrives as an override — fold it in,
exactly as §1 says. `## Handoff` accepts all four values and `/dispatch` routes on all four.

Write the answer into the plan's `## Handoff` **before** you do anything else with it — `both` for
Proceed, `nothing` for Just save (the plan-check script's `--set-handoff <value>` does exactly this). That one line is the recovery path: if this turn dies, `/dispatch`
reads the answer from the file instead of asking the operator to decide twice.

**Then commit the plan — that file and nothing else — on the trunk in the main checkout**, whichever
option was chosen:

```sh
git add -- <plan-path> && git commit -m "<the project's commit style>: plan <what it builds>" -- <plan-path>
```

A worktree branches from the trunk, so an uncommitted plan is not in the run's checkout at all, and
the dispatch preflight blocks on the dirty main checkout (`13`). The pathspec on both commands is the
point: other cockpits share this checkout and may have their own files open, and `git add -A` or a
bare `git commit` would sweep those into your commit. Do not push; `/land` pushes the trunk. If the plan is edited again before
dispatch (a free-text override folded in), commit it again.

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

**Do not end the interview here with the plan written and nothing running.** A handoff answer reads
like a label for a state; it is an instruction to act.

**The answer to §6 is the approval. Act on it as your first action in that turn** — not a summary,
not a closing paragraph, not "let me know if you want me to start", and **not an `ExitPlanMode`
round**: this skill does not enter plan mode (§0), and the operator has already approved.

| `## Handoff` | Your immediate next action |
|---|---|
| `both` | `Skill(dispatch)` — it reads `## Handoff` itself and lands when green |
| `dispatch` | `Skill(dispatch)` |
| `deliver` | `Skill(dispatch)` — the foreground variant; still a worktree |
| `nothing` | nothing. Say the plan is ready and stop. |

## 7a. Interview in parallel, then own what you dispatch

**One interview, one session, and it stays the cockpit for its own runs.** Interviews run in parallel,
one per feature, because mixing three features' interviews into one context degrades the questions —
and because the blocking resource is the operator, not the agent. Serialising interviews would
serialise the operator's answering. Run as many as they can answer
round-robin, about three.

**So dispatch from here; never hand the plan to another session.** `/deliver` §7 reports `DELIVERED`
to whoever dispatched it, so the session that dispatched is the session that must be alive to hear it
and the session that lands the branch. Everything else about owning a run — the watcher, which
signals mean what, and the three seams where the relay drops the baton — lives in `/dispatch` §0b,
§5 and §6, which is where you will be when it matters. It is not repeated here.
