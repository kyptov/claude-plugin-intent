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

**A skill's `model:` frontmatter does not change the cockpit's model** — measured over the week of
2026-10-19, with `model: sonnet` on this skill and `/land`, 99.9% of cockpit tokens ran on the
session's own model. Dispatching, waiting and reporting are babysitting, not thinking, so what keeps
the cockpit cheap is keeping it plan-sized (never implementing here) and, when cost matters, a
separate `claude --model sonnet` cockpit for dispatch and land, with interviews (`/intent`) in an
Opus session that hands it the plan.

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
.claude/scripts/dispatch/preflight.sh <plan-path> --waitfor "${CLAUDE_PLUGIN_ROOT}/skills/dispatch/wait-for.sh"
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
  denies the write anyway, so ignoring it only burns a run. Staleness (idle past the declaration's
  threshold) and a holder that is no longer a live session are both settled by the scripts, never
  by eye.
- **`12` is a file-set intersection, not a feeling.** The script intersects the paths the plan names
  with each unlanded branch's diff. A non-overlapping unlanded branch is reported and does **not** block — but `/land` it the same day.

### 1a. Blocked by another session — route on the `VERDICT` line

Exits 10–13 are blocks another session can hold: a landing in flight, its lease, its unlanded
branch, its uncommitted paths. Two cockpits can each hold what the other waits for, and the operator
— the only one either would ask — cannot see that cycle. So the preflight prints a verdict from the
plugin's `wait-for.sh`, which records who waits on whom (`.claude/waits/`) and breaks a cycle by
making one session yield. **Never ask the operator to make this session wait on another session;
the script decides.**

| Verdict | What you do |
|---|---|
| `CLEAR` | nothing another session holds is in the way; with exit 0, dispatch |
| `WAIT` | run the `WAIT-CMD` line verbatim with `Bash` `run_in_background: true`, `timeout: 7200000`, and end your turn. Its completion is the wake-up: it ends `CLEAR` → re-run the preflight; `YIELD` → as below; `TIMEOUT` → report the holder and the wait, plainly, notify (§4), and stop |
| `YIELD` | this plan does not start. Report `yielded to <session> to break a wait cycle` and what the script released (your lease) or listed (uncommitted paths for the operator to commit or stash), in one line, and notify (§4). Do not re-dispatch it this turn |
| `FIX` | no live session holds the block, so waiting cannot clear it: `12` → the branch's cockpit is gone, so §5's seams table (*cockpit ended first*) applies; `13` → report the paths for the operator to commit or stash; anything else → report the block. Notify (§4) |

A block with **no `VERDICT` line** means the project's preflight predates this contract: stop, say
so, notify (§4), and point at `${CLAUDE_PLUGIN_ROOT}/skills/dispatch/BOOTSTRAP.md` to regenerate it.

None of these is a question. A report that a plan yielded, or that its paths need committing, is a
statement; the operator acts on it when they choose.

### 1b. The branch name

Then one check of your own, per plan: the run will name its branch `<prefix>/<slug>` (the
declaration's branch namespace, default `wt`; the slug is the plan's file name without `.md` and
without a trailing `-plan`). If that branch already exists, an earlier run of this plan is unlanded —
`/land` it or remove it first; never dispatch on top of it:

```sh
git show-ref --verify --quiet refs/heads/<prefix>/<slug> && echo "taken"
```

A plan whose header carries **`after: <slug>`** is the second half of a split (`/intent` §3's plan
budget): it starts only once `<slug>` has landed — its plan file is gone from the trunk, because
`/land` deletes it. Until then it does not start: report `<slug> waits for <after-slug> to land`, and
dispatch it from §5 in the turn that lands `<after-slug>`.

### 1c. A run slot — at most `max_parallel_runs` runs at once

The account's session limit is shared by every cockpit and every run; past it, all of them freeze.
So the last check before a launch, per plan, after the preflight is clear, is a run slot — the
declaration's `max_parallel_runs`, default 5:

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/wait-for.sh check --resource run-slot --max-runs <max_parallel_runs> \
  [--prefix <branch namespace>]
```

It counts the live runs of every cockpit in this repo (a worktree on `<prefix>/*` whose cockpit is
alive and whose run has written no verdict yet) and the cockpits queued ahead of this one. `CLEAR`
claims the slot: launch (§3). `WAIT` carries `position=` and `running=`: this plan does not launch.
Print `<slug>: queued — position <n>, <running> running`, notify (§4), run its `WAIT-CMD` exactly as
§1a's `WAIT` row says, and end your turn; on `CLEAR`, re-run the preflight and launch; on `TIMEOUT`,
report and notify. A wave claims one slot per plan: check each in turn, launch the ones that got
`CLEAR`, queue the rest behind one wait.

## 2. Read `## Handoff` from the plan — it is already decided

`/intent` asked the operator, as its last question, how far to go automatically. That answer is in the
plan's `## Handoff` section — §1's preflight already read it and printed it, and rejects a template
placeholder (`<nothing | dispatch | …>`) the same as a missing answer. **Honour it; do not re-ask.**

| Handoff | What you do |
|---|---|
| **`ship`** — the normal case, and what `/intent` offers | start the run in the background, invoke `/land` yourself when it reports green, and `/land` runs the declaration's deploy commands after the landing (`/land` §8). §3 → §4 → §5, one continuous sequence |
| `both` | the same, but `/land` ends with its "Deploy?" question instead of deploying — the operator ships |
| `dispatch` | start the run, but stop at a finished branch and report it is ready for `/land` |
| `deliver` | the same `Agent` call in the **foreground** (`run_in_background: false`), so the operator watches it in this session |
| `nothing` | you should not have been invoked; say so and stop |

**Every handoff that runs, runs now** — there is no deferred or queued path (§3). The three middle
rows arrive only as a free-text override at `/intent` §6, which offers `ship` or nothing; treat
`ship` as the default reading of any ambiguous answer.

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
deferred path** — every dispatch starts now, or queues for a run slot (§1c), or waits on another
session (§1a); nothing else delays it. "Tonight" is not an option to offer; if the operator wants
work to start later, they say so and nothing in this skill runs.

Once the `Agent` calls have returned, release the slot claims — each run's worktree now counts
itself: `"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/wait-for.sh clear`.

Report the wave in one line per run — the plan, and that it started — then end your turn.

## 4. While runs work

The harness tells you when a run ends; you do not ask. When a completion notification arrives:

1. Read the run's final message. Its `DELIVERED <slug> — gates: …` line is the verdict, and the
   notification's worktree path is where the branch lives.
2. Act per §5: land on `gates: green` when `## Handoff` is `ship` or `both`; report anything else.

When the operator asks "what is running" — or on their first message of the day — answer in plain
words, not in tool output:

- which features are in flight (your background runs still going), and in which worktree;
- which finished, and what each decided alone (from `## Decisions (agent-made)`);
- what is **not delivered**, per plan — the operator's next pickup;
- anything waiting on their call, and any branch that failed to land.

`git worktree list` and `git branch --list '<prefix>/*' --no-merged <trunk>` show what the repo
holds beyond your own runs; `"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/wait-for.sh list` shows which
sessions are waiting on which.

### Notify at every terminal event — and only then

The operator should never have to ask "status?". Send one `PushNotification` and print the same
line in the reply at each of these, one line each:

| Event | Line |
|---|---|
| a run's final report arrives green, `Handoff` is `dispatch` | `<slug>: green — ready to /land` |
| a run's final report arrives `RED` or `not-run`, or with no verdict | `<slug>: RED — <failing gate or stop reason> — needs you` |
| `/land` finishes | `/land` §5b sends it: `<slug>: landed <short hash>` or `<slug>: not landed — exit <code> — <what it needs>` |
| a wait ends `TIMEOUT` | `<slug>: wait timed out — <resource> held by <holder> — needs you` |
| a block this cockpit cannot clear (`YIELD`, `FIX`, no `VERDICT`, preflight `20`) | `<slug>: BLOCKED — <reason> — needs you` |
| a plan queued for a run slot (§1c) | `<slug>: queued — position <n>, <running> running` |

A green report with `Handoff: ship` or `both` gets no line of its own: the landing follows in the
same turn and `/land`'s line says how it ended. Never on a slice, a wave start, or a wait that is still going.

## 5. Then land

Runs are not done until `/land` has put them on `main` as one commit each. A finished run with
an unlanded branch is the failure mode this whole pipeline exists to prevent — chase it the same day.

**For `Handoff: ship` or `both`, land on the run's own `DELIVERED … gates: green` verdict — nothing else.**
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
| cockpit → land | nobody invokes `/land`, and a finished branch waits | `Handoff: ship` or `both` means you land it, on the verdict, in the same turn the notification arrives |
