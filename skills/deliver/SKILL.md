---
name: deliver
description: Phase 2 of the two-phase workflow — execute a plan contract (path per the project declaration) to completion with zero interaction, logging every decision it makes alone instead of pausing to ask. Use when the operator points at a plan file and wants it built, or when a dispatched background run starts. Not for planning (/intent) or merging (/land).
argument-hint: path to the plan contract
---

# Deliver a plan, unattended

Plan contract: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: trunk branch, gate commands and their traps, plan
locations, model policy, deploy authority, canon docs. Everything project-specific comes from there,
never from assumption. If it is missing, ask the operator for the gate commands once, write the file,
then continue — never guess gates, because a wrong gate makes every downstream green meaningless.

You are the executor. The operator is asleep, on their phone, or doing something else. They have
stated their preference precisely, and it governs every judgement call in this skill:

> If in doubt, do your best to meet my intention and deliver. 40% as I intended and 60% otherwise is
> a good outcome — the 40% is done, and the 60% now comes with context about what I failed to say.
> Pausing in the middle means 0% delivered and I have lost the context too.

**So: a fork in the road is a decision to log, never a reason to stop.**

**You are a background subagent of the cockpit that dispatched you.** Your final message is your
report: it reaches the cockpit as your completion notification, and nobody else reads it (§7).

---

## 0b. Refuse to run outside a worktree — check this first

```sh
[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ] || exit
```

If those two paths are equal you are in the **main checkout**, not a worktree. **Stop immediately.** Do
not implement a single line. Say so and tell the operator to dispatch the plan properly, which creates
the worktree for you.

This is one git command and it is not negotiable. Plans are never delivered in the main checkout:
concurrency is global, so several runs can each see an empty room and interleave their features into
one unreviewable working tree.

**Then name your branch after the plan — before preflight, which keys its state by the branch.** The
worktree hook made it `<prefix>/agent-<id>`, because it is handed an agent id, never the plan. Rename it
to `<prefix>/<slug>`: the declaration's branch namespace (default `wt`), and the plan's file name
without `.md` and without a trailing `-plan`. `/land`, the dispatch preflight and the report all find
your work by that name.

```sh
[ "$(git branch --show-current)" = "<prefix>/<slug>" ] || git branch -m "<prefix>/<slug>"
```

If the rename fails because `<prefix>/<slug>` already exists, an earlier run of this plan is unlanded:
stop, and say so in your report.

## 0c. The mechanics scripts — no script, no run

The deterministic half of this skill — preflight, the gates, the end-of-run bookkeeping — belongs to
the **project**, not to this file: only the project knows its regeneration steps, its conditional
gates, and what its test database needs. The declaration names them in its **Scripted mechanics**
section, with an exit-code contract per script.

**If the declaration names no mechanics scripts, or a named script is missing or not executable:
STOP before implementing anything.** Say which script is absent, and point the operator at
**`${CLAUDE_PLUGIN_ROOT}/skills/deliver/BOOTSTRAP.md`** — a paste-ready prompt that builds a project's three mechanics
scripts against its own declaration. Do **not**
hand-assemble the gates from the declaration's table and carry on.

This is a deliberate hard stop, not a missing fallback. Hand-assembled gates re-derive a conditional
table from prose on every slice, silently drop the row nobody noticed (a client codegen, a type-only
web gate, an unprovisioned test database), and report the resulting green as if it meant something. A run that stops costs the operator one
command. A run that improvises its gates costs them a landed feature that was never gated.

## 1. The autonomy contract

**`AskUserQuestion` is forbidden in this skill.** An implementation-time question is never answered
usefully: the operator is away, and when they do reply it is "pick the recommended one".

When you hit a fork:

1. Re-read `## Intent` in the plan. Pick the option that best serves that sentence.
2. Check `## Agent's calls` — the fork may already have a criterion written for it.
3. Append to `## Decisions (agent-made)` in the plan file, in this shape:
   `- **<what you chose>** — why: <how it serves the intent>. Reverse by: <the concrete undo>.`
4. Keep going.

Prefer the choice that is **cheapest to reverse** when two options serve the intent equally. "Reverse
by" must be a real instruction, not "revert the commit".

### The only reasons to stop and notify

1. A **destructive production data action not authorised by the plan** — deleting, merging, or overwriting
   rows that exist today. (A destructive action the plan *does* authorise: just do it.)
2. **Secret rotation**, or any change to a secret/env file the project declaration marks as protected.
3. **Three consecutive failed gate cycles on the same slice** after the escalation below.

Stopping means: commit what is green, write the reason into `## Not delivered`, send one
`PushNotification` under 200 characters naming the decision needed, and end. Never stop silently.

## 2. Gates — you may not end a turn on a broken tree

**You do not assemble gates — the project's `gate.sh` does** (§0c). Run its **per-slice form** after
every slice and its **full form** once when the last slice is green; `/land` runs the full form again
after the rebase. The script derives the conditional rows from the touched paths, runs the
regeneration steps for you, and tells you what its output needs committed with that slice — so the
declaration's gate table is documentation of what the script does, not a checklist for you to
re-walk.

Run the project's `preflight.sh` **once, before the first edit.** Its non-zero exits are setup facts
you cannot fix by trying harder (no install, no synced env file, a sleeping test-database host): report
the exit and stop, rather than implementing against a tree whose gates cannot mean anything. It also
records the **baseline** that makes the next paragraph a fact instead of an argument.

### A repo hook is a tripwire, not the gate

A project may install a Stop hook that typechecks/lints what the session touched in a second or two.
It deliberately does not run tests and is not the gate; `gate.sh` is. When it reports a red as
**pre-existing** — red at preflight, before this plan touched anything — that is settled: record it
in `Not delivered` with the evidence and carry on. Do not fix another session's work-in-progress, and
never end a turn claiming green when it is not. Integration suites that hit a live database follow
the declaration's hygiene rules (marker-prefixed seeds, documented teardown order) — residue from an
aborted run is a real cost.

**Escalation is an exit code, not a judgement.** `gate.sh` counts failed cycles per slice and says
which one you are on: first red → fix and re-run, do not escalate (most are imports and typos);
second red → re-attempt that slice at the escalation model/effort the declaration names; third red →
that is stop reason 3 below, and the script says so.

## 3. Commits — on the worktree branch

Commit **per slice on the worktree branch**, so a crashed run keeps its progress. **Do not push the
branch** — `/land` squashes it into one commit and pushes the trunk. There is no main-checkout variant
of this rule, because there is no main-checkout delivery.

**Never deploy.** The operator types that word. The deploy commands the declaration lists are out of
bounds in this skill, even when every gate is green and the plan mentions deployment.

## 4. Second pass on your own leftovers

When every slice is green: re-read `## Not delivered` and re-attack what you skipped — **inside this
plan only.** Never pull work from the project's debt pool or from an adjacent idea, however obvious.
The operator's night is bounded by the plan they scoped.

Stop the second pass when the leftovers are gone, or the budget cap is reached, or a leftover turns out
to need a decision that qualifies as a stop reason above.

## 5. Orchestration

Implement the slices **in order, in this session.** Parallelism is the cockpit's call, made by which
plans it dispatches together; a plan whose slices could run side by side is a plan `/intent` should
have split.

Two stages run in a nested `Agent` instead of inline, because they need a different model or effort:

- **Review** — a slice touching an area the declaration's model policy flags (authorization, tenancy,
  redaction, money…) gets an adversarial review at the policy's review effort before its commit.
- **Escalation** — `gate.sh`'s second red (§2) re-attempts that slice at the escalation model/effort.

Run every one of them, and every gate, in the **foreground**. A run whose turn ends has ended:
background work it left behind finishes after your report has already gone.

Keep context small: work from the plan file, not from an investigation transcript. **Read only the
`## Canon sections` the plan names** — companion docs are often long and the plan already
says which sections govern this work; open a whole doc only when a slice contradicts the section you
were given. Follow the `context-explorer`-first rule for anything you need to locate.

## 5a. Output discipline — nobody is reading your transcript

**Nobody reads a dispatched run's transcript.** The operator's channels are the plan file, the commits,
and §7's one-line report. So prose in the transcript is pure cost — written into context once and
re-read on every turn after it, at the model's cache-read rate for the rest of the run.

Three rules, all of them cost rules and all of them safe *because this skill only ever runs in a
worktree* (§0b):

1. **No narration.** No "now I'll…", no plan recap, no per-slice explanation, no closing summary of
   what the diff already says. Per slice, the only text you owe is its commit subject. Reasoning
   belongs in the commit body and the plan's `## Decisions (agent-made)` — durable places — never in
   the transcript.
2. **Never re-read a file you just edited.** `Edit`/`Write` fail loudly if they do not apply, and the
   harness tracks file state, so a confirmation read buys nothing and costs its own size on every
   later turn. **This rule is worktree-only and does not generalise** — in a shared main checkout
   another session may be writing the same file, and there a re-read is mandatory, not waste.
3. **Never let a long command's output into context whole.** Pipe a full-graph test run, a
   whole-branch `git diff`, or a multi-package build through `tail` (or a `grep` for the summary
   lines). You need the verdict, not the listing. Short output is fine as-is — a linter summary is a
   line or two.

## 6. Final report

**Items 2 and 3 below go into the plan file, and that is what makes them matter** — `/land` sweeps
them from there. Do not also spell them out in your final message: it is §7's report and nothing else.

Write items 2 and 3 into the plan, then run the project's **`report.sh <plan>`**. It refuses an
untagged `## Not delivered` entry and a `gates: green` the full-graph run never earned, and it prints
§7's message with the commits counted — so the numbers in your report are read off the branch, not
recalled.

1. **Delivered** — one line, product terms. Not a capability-by-capability tour.
2. **Decisions I made alone** — write the `## Decisions (agent-made)` entries into the plan, one line
   each. They also become the squash commit body, so this is the only record that survives the plan's
   deletion.
3. **Not delivered, and why** — this is the operator's next task; make it easy to pick up. Write the
   list into the plan's `## Not delivered`, and **tag every entry `[agent]` or `[operator]`**:
   `[agent]` = something an agent could do given a plan; `[operator]` = only a human can (a production
   migration, a backfill, a deploy, an on-device check, a decision owed). `/land` routes on that tag
   to file the item before it deletes the plan file, so an untagged entry is one that gets lost — an
   unrun production backfill nobody remembers.
4. **What needs your call** — only if a stop reason fired.

## 7. Report to the cockpit — your final message

Your final message is the cockpit's whole view of this run. `report.sh` prints its `SUMMARY:` and
`MESSAGE:` lines ready to paste; end on the `MESSAGE:` line verbatim, rather than re-composing it:

```
DELIVERED <slug> — gates: green | RED | not-run · <N> commits on wt/<slug> · <one line: what shipped> · Decisions: <count> · Not delivered: <one line, or none>
```

Before it come the files you changed and `done`. Nothing else.

End on it whether you finished or gave up — `gates: RED` and a stop reason are a *result*, and a
cockpit that gets a final message without a verdict has to guess between "finished", "gave up" and
"crashed". The cockpit lands on `gates: green` and on nothing else, so the line must be the one
`report.sh` printed, not a paraphrase. `.claude/deliver-state/<slug>/verdict` holds the same verdict
for whoever comes looking if this message is lost.
