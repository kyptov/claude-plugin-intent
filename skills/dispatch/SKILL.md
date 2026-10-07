---
name: dispatch
description: Cockpit dispatcher — take an approved plan contract and start its unattended /deliver run as a background subagent in a worktree of its own; also reports the status of running work and unlanded branches. Use after /intent is approved, or when the operator asks to start, queue, check, or parallelise implementation work. Not for interviewing (/intent), implementing (/deliver), or merging (/land).
argument-hint: plan path(s)
---

# Dispatch a plan into its worktree

Target: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: trunk branch, gate commands and their traps, plan
locations, model policy, deploy authority, canon docs. Everything project-specific comes from there,
never from assumption. If it is missing, ask the operator for the gate commands once, write the file,
then continue — never guess gates, because a wrong gate makes every downstream green meaningless.

You are the cockpit: a long-lived `--remote-control` session on a machine that stays on, reachable from any
device. **You never implement a feature yourself** — that keeps your context plan-sized, your cost
low, and your replies fast on a phone. You interview, dispatch, report, and land.

**The cockpit runs in `bypassPermissions` mode.** A run is a subagent of this session and inherits its
permission mode, so in any other mode the run's first permission prompt surfaces here and parks the
run until someone answers it — an unattended run that is not unattended. If this session is not in
`bypassPermissions`, say so and stop before dispatching. Blast radius is the worktree, not the mode:
`/deliver` forbids deploy and any production-destructive action the plan did not authorise.

---

## 0b. The session that dispatches owns the run

Every run you start is a **background subagent of this session**. Its final report — `/deliver` §7's
`DELIVERED` line — comes back to this session as the agent's completion notification, and to nobody
else, so this is the session that hears the verdict and the session that lands the branch.

**A run lives exactly as long as this session.** Keep the cockpit open until every run it started has
landed or been reported. If the cockpit ends first, its runs end with it: their worktrees and commits
stay on disk, and §5's seams table says how to pick them up.

**Do not poll for what you will be told.** The completion notification is the only signal that means
done, and it arrives on its own. No watcher, no `/loop`, no `ScheduleWakeup` for progress: after
dispatching, end your turn.

**What no session can see is the repo.** Unlanded branches and stale worktrees are project-global and
outlive the session that made them, so a finished feature can be stranded there. That is a cadence,
not a long-lived owner; `/debt-review` covers it.

## 1. Guard first — the project's dispatch preflight, not five commands you interpret

Never dispatch into a dirty situation. The declaration's **Scripted mechanics** section names the
project's dispatch preflight; run it per plan and route on its exit code:

```sh
.claude/scripts/dispatch/preflight.sh <plan-path>
```

| | |
|---|---|
| `0` | clear to dispatch |
| `10` | `land.lock` held — a landing is in flight (a *live* one: the project's preflight ignores a lock whose process is gone) |
| `11` | main-checkout lease held and fresh (its own lease excluded) |
| `12` | an unlanded branch **overlaps this plan's files** — `/land` it first |
| `13` | main checkout dirty |
| `20` | `## Handoff` missing or a template placeholder — §2 |

**If the declaration names no dispatch preflight, or the script is missing: stop and say so**, and
point the operator at **`${CLAUDE_PLUGIN_ROOT}/skills/dispatch/BOOTSTRAP.md`** — a paste-ready prompt that builds this
script against the project's own declaration. Same rule as `/deliver` §0c: the checks are
project-shaped (the trunk, the plan template's `- Files:` lines, which lock files exist), so they live
in a script, never re-derived from prose.

Two of those codes carry judgement worth knowing:

- **`11` blocks ad-hoc SOURCE edits in the main checkout, not dispatching.** The project's guard hook
  denies the write anyway, so ignoring it only burns a run. A lease idle past 45 minutes is stale and
  takeable; clear a known-dead one with `rm .claude/main-checkout.lock`.
- **`12` is a file-set intersection, not a feeling.** The script intersects the paths the plan names
  with each unlanded branch's diff. A non-overlapping unlanded branch is reported and does **not** block — but `/land` it the same day.

Then one check of your own, per plan: the run will name its branch `<prefix>/<slug>` (the
declaration's branch namespace, default `wt`; the slug is the plan's file name without `.md` and
without a trailing `-plan`). If that branch already exists, an earlier run of this plan is unlanded —
`/land` it or remove it first; never dispatch on top of it:

```sh
git show-ref --verify --quiet refs/heads/<prefix>/<slug> && echo "taken"
```

## 2. Read `## Handoff` from the plan — it is already decided

`/intent` asked the operator, as its last question, how far to go automatically. That answer is in the
plan's `## Handoff` section — §1's preflight already read it and printed it, and rejects a template
placeholder (`<nothing | dispatch | …>`) the same as a missing answer. **Honour it; do not re-ask.**

| Handoff | What you do |
|---|---|
| **`both`** — the normal case, and what `/intent` offers | start the run in the background, and invoke `/land` yourself when it reports green. §3 → §4 → §5, one continuous sequence |
| `dispatch` | same, but stop at a finished branch and report it is ready for `/land` |
| `deliver` | the same `Agent` call in the **foreground** (`run_in_background: false`), so the operator watches it in this session |
| `nothing` | you should not have been invoked; say so and stop |

**Every handoff that runs, runs now** — there is no deferred or queued path (§3). The two middle rows
arrive only as a free-text override at `/intent` §6, which offers `both` or nothing; treat `both` as
the default reading of any ambiguous answer.

If `## Handoff` is missing or unreadable, the plan did not come through `/intent`. Ask once, then
write the answer into the plan before doing anything else.

## 3. Start the run — one `Agent` call per plan

**Any plan you dispatch is implemented in a worktree.** Not the main checkout, not "just this once" —
a point-in-time cleanliness check cannot see a write that lands half an hour later. `isolation:
"worktree"` gives the run one, and the plugin's `WorktreeCreate` hook
(`${CLAUDE_PLUGIN_ROOT}/skills/dispatch/worktree-create.sh`) builds it before the run's first turn:

- the worktree at `../<project>-wt-<agent id>`, on `<prefix>/<agent id>` from the trunk — `/deliver`
  renames the branch to `<prefix>/<slug>` as its first act, because the hook is handed an agent id,
  never the plan;
- the project's **`.claude/scripts/dispatch/worktree-setup.sh <worktree>`**, run from the main
  checkout, when the project has one — the install, synced env files, a database of the run's own,
  whatever makes the worktree gateable. Without it, the install is inferred from the lockfile and a
  `worktree:sync` package script runs if the repo declares one.

A setup that fails tears down what it built and fails the `Agent` call with the hook's output — a
setup problem to report, with nothing left behind to clean.

```
Agent({
  description: "deliver <slug>",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "<impl model>",
  effort: "<impl effort>",
  run_in_background: true,
  prompt: "You are a dispatched /deliver run. Invoke the Skill tool with skill \"workflow:deliver\" and args \"<plan-path>\", and follow it to the end. Nobody is watching: your final message is your report to the cockpit."
})
```

Model and effort come from `.claude/workflow.md` ("Model policy"); the `model` parameter takes a
family alias (`opus`, `sonnet`, …) and resolves to its latest model. The run's prompt cache follows
`subagentPromptCacheTtl`, not the cockpit's `promptCacheTtl`: a run's turns are back to back, so a
5-minute TTL fits it, while the cockpit waits on runs for many minutes at a time and keeps 1 hour.

Dispatch 2-4 runs **in one wave** — several `Agent` calls in one message — not trickled. Parallelism
is decided here, by which plans go in a wave; a run implements its own slices in order. **There is no
deferred path** — every dispatch starts now. "Tonight" is not an option to offer; if the operator
wants work to start later, they say so and nothing in this skill runs.

Report the wave in one line per run — the plan, and that it started — then end your turn.

## 4. While runs work

The harness tells you when a run ends; you do not ask. When a completion notification arrives:

1. Read the run's final message. Its `DELIVERED <slug> — gates: …` line is the verdict, and the
   notification's worktree path is where the branch lives.
2. Act per §5: land on `gates: green` when `## Handoff` is `both`; report anything else.

When the operator asks "what is running" — or on their first message of the day — answer in plain
words, not in tool output:

- which features are in flight (your background runs still going), and in which worktree;
- which finished, and what each decided alone (from `## Decisions (agent-made)`);
- what is **not delivered**, per plan — the operator's next pickup;
- anything waiting on their call, and any branch that failed to land.

`git worktree list` and `git branch --list '<prefix>/*' --no-merged <trunk>` show what the repo
holds beyond your own runs.

Only send a `PushNotification` for something that changes what they would do next: a run needs a
decision, or a branch would not land. Not for progress.

## 5. Then land

Runs are not done until `/land` has put them on `main` as one commit each. A finished run with
an unlanded branch is the failure mode this whole pipeline exists to prevent — chase it the same day.

**For `Handoff: both`, land on the run's own `DELIVERED … gates: green` verdict — nothing else.**
`gates: RED` or `not-run` is a report to the operator, not a licence to land, and so is a branch that
merely holds commits: it reads the same whether the run finished or died mid-slice.

### Where the relay drops the baton

`/intent` → `/dispatch` → `/deliver` → `/land` is a relay, so every hop is a place the baton can be
dropped:

| Seam | How it fails | What you do |
|---|---|---|
| dispatch → run | the `WorktreeCreate` hook fails — install, sync or the project's setup script | the `Agent` call returns the hook's output and nothing was left behind; report the setup failure |
| run → cockpit | the run ended without a `DELIVERED` line — it crashed or ran out of turns | read `<worktree>/.claude/deliver-state/<slug>/verdict`. A green verdict there is the run's own judgement: land on it. No verdict → report to the operator; do not land |
| run → cockpit | the run ended with nothing on its branch — it stopped before its first commit, or `/land` exits 24 | Claude Code keeps every agent worktree, and the project's setup may have made a database for it. Report the run, then remove it — teardown, worktree, branch: `echo '{"worktree_path":"<worktree>"}' \| "${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/worktree-remove.sh` |
| cockpit ended first | the session closed while runs were working, and its runs ended with it | the worktree holds the commits, on `<prefix>/<slug>` (or `<prefix>/agent-<id>` if it died before renaming). A verdict file says green → `/land`; otherwise tell the operator, who removes the worktree and branch and dispatches again |
| cockpit → land | nobody invokes `/land`, and a finished branch waits | `Handoff: both` means you land it, on the verdict, in the same turn the notification arrives |
