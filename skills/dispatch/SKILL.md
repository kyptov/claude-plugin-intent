---
name: dispatch
description: Cockpit dispatcher — take an approved plan contract, create its worktree, and start the unattended /deliver run in it; also reports the status of running work and unlanded branches. Use after /intent is approved, or when the operator asks to start, queue, check, or parallelise implementation work. Not for interviewing (/intent), implementing (/deliver), or merging (/land).
argument-hint: plan path(s)
---

# Dispatch a plan into its worktree

Target: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: trunk branch, gate commands and their traps, plan
locations, model policy, deploy authority, canon docs. Everything project-specific comes from there,
never from assumption. If it is missing, ask the operator for the gate commands once, write the file,
then continue — never guess gates, because a wrong gate makes every downstream green meaningless.

You are the cockpit: a long-lived `--remote-control` session on the operator's always-on machine, reachable from any
device. **You never implement a feature yourself.** That is what keeps your context plan-sized, your
cost low, and your replies fast on a phone. You interview, dispatch, report, and land.

---

## 0b. The session that dispatches owns the run

You never implement a feature yourself — that is what keeps your context plan-sized, your cost low,
and your replies fast on a phone. But you do own every run you start: `/deliver` §7 reports
`DELIVERED` back to whoever dispatched it, so this session has to be alive to hear it, and it is the
session that lands the branch.

**One watcher per session, watching its own runs only.** `watch-runs.sh` derives worktrees from git,
so it reports every run in the repo including other sessions' — report only your own. And do not poll
for what you will be told: `DELIVERED` is the completion signal and the operator's session list is the
liveness signal, so §5's loop exists for one narrow case (a run *parked* on a dialog) and should be
sized for that, not for progress — a loop polling for progress reports nothing new almost every tick.

**What no session can see is the repo.** Unlanded branches, stale worktrees and orphan runs are
project-global and do not appear in any session list, so a finished feature can be stranded there.
That is a cadence, not a long-lived owner; `/debt-review` covers it.

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
script against the project's own declaration. Same rule as `/deliver` §0c, same reason — the checks are project-shaped (the trunk, the plan template's
`- Files:` lines, which lock files exist), and a cockpit that re-derives them from prose eventually
reads a fresh lease as stale or blocks a wave over an unlanded branch that touches nothing this plan
will.

Two of those codes carry judgement worth knowing:

- **`11` blocks ad-hoc SOURCE edits in the main checkout, not dispatching.** The project's guard hook
  denies the write anyway, so ignoring it only burns a run. A lease idle past 45 minutes is stale and
  takeable; clear a known-dead one with `rm .claude/main-checkout.lock`.
- **`12` is a file-set intersection, not a feeling.** "Unlanded work in the plan's area" used to be
  eyeballed; the script intersects the paths the plan names with each unlanded branch's diff. A
  non-overlapping unlanded branch is reported and does **not** block — but `/land` it the same day.

## 2. Read `## Handoff` from the plan — it is already decided

`/intent` asked the operator, as its last question, how far to go automatically. That answer is in the
plan's `## Handoff` section — §1's preflight already read it and printed it, and rejects a template
placeholder (`<nothing | dispatch | …>`) the same as a missing answer. **Honour it; do not re-ask.**

| Handoff | What you do |
|---|---|
| **`both`** — the normal case, and what `/intent` offers | create the worktree, start the unattended run in it, and invoke `/land` yourself when it reports green. §3 → §5 → §6, one continuous sequence |
| `dispatch` | same, but stop at a finished branch and report it is ready for `/land` |
| `deliver` | create the worktree, then run `/deliver` in it in the foreground so the operator watches (§3, last note) |
| `nothing` | you should not have been invoked; say so and stop |

**Every handoff that runs, runs now** — there is no deferred or queued path (§3). The two middle rows
arrive only as a free-text override at `/intent` §6, which offers `both` or nothing; treat `both` as
the default reading of any ambiguous answer.

If `## Handoff` is missing or unreadable, the plan did not come through `/intent`. Ask once, then
write the answer into the plan before doing anything else.

## 3. Make the worktree and start the run — one script, every time

**Any plan you dispatch is implemented in a worktree.** Not the main checkout, not "just this once" —
a point-in-time cleanliness check cannot see a write that lands half an hour later, and that is how
several features once got interleaved into one working tree. The worktree, the install, the
project's worktree sync, the folder pre-trust, the per-project `tmux` socket, the Remote Control
session, the registration wait, the plan hand-off and the pane check are **one deterministic
script** next to this skill — never re-derived as prose, because a hand-run sequence is where waves
quietly fail to start (a worktree prepared and never used; a session launched and never sent its plan).

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/launch-run.sh <plan-path> --model <impl model> --effort <impl effort> --tag <project tag>
```

Read model/effort from `.claude/workflow.md` ("Model policy") and `--tag` from its session-tag line. Pass `--install` / `--sync` from the
declaration's worktree-setup section when it names them (the script otherwise infers the install from
the lockfile and runs a `worktree:sync` package script if one exists); `--trunk` only if the trunk is
not `origin/HEAD`; `WT_BRANCH_PREFIX` if the declaration's branch namespace is not `wt`. The script refuses to run from an unpinned
session (`CLAUDE_CONFIG_DIR` unset), refuses a slug whose worktree or branch already exists, and ends
with two lines you act on:

```
WT=<path> BRANCH=wt/<slug> SOCK=impl-<proj> SESSION=impl-<proj>-<slug> NAME=<tag>-<hex>·<slug>
COCKPIT_PID=<pid> SENT=yes|unconfirmed
```

### Session naming — a short key at the FRONT, a human name after it

A session list truncates the END of a name, so the pairing key has to be first; everything after it
is for the operator, who runs 3-4 cockpits at once and needs to see *which feature* each one is:

```
ln-de · Money board totals       <- cockpit
ln-de · impl money-board-sweep   <- its run
ml-6a · Consumption metering     <- another project's cockpit
ml-6a · impl zero-consumption    <- its run
```

**The key is `<tag>-<hex>`, not the cockpit's name.** Two sessions pair iff their names start with
the same key, which is what `watch-runs.sh --mine <key>` filters on — so renaming a cockpit's human
half never orphans its runs. `<tag>` is the project's two-letter abbreviation from the declaration
(`loadnex` → `ln`, `ml-billing` → `ml`); `<hex>` is reused from the harness's own derived session
name, already unique among live sessions.

**The script also names the cockpit**, because a session whose `nameSource` is merely `derived` is
displayed by its auto-generated title instead of its name — exactly why a cockpit row and its runs
look unrelated today. The human half comes from `--cockpit-title`, else the plan's own `# ` heading,
which the template already requires to be the capability in plain words. It refuses to touch a name
the operator set explicitly, and refuses while this cockpit has live runs, which pair by that key.

**That rename is cosmetic, and nothing may depend on it.** It is a write into the cockpit's registry
FILE, and the live cockpit process never reads that file back — it keeps its own name state — so
Claude Code's conversation auto-titler overwrites the poke with its own conversation title, silently.
Measured on the 2026-09-18 15:02 wave: four cockpits renamed, all four re-titled 3–5 seconds later,
every run in the wave left holding a `cockpit:` address that no longer resolved. The
`nameSource = derived` guard cannot prevent this — it reads the state *before* the titler fires, and
a cockpit dispatching before it has ever been auto-titled is the normal case.

**So the return address is a sessionId, not a name.** `launch-run.sh` writes the cockpit's
sessionId/pid/key to `$CLAUDE_CONFIG_DIR/dispatch-runs/<munged worktree>` (outside the repo — an
untracked file under the worktree's `.claude/` is one `git add -A` away from the trunk), and the run
resolves it to whatever the cockpit is called *at report time*:

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/cockpit-addr.sh [worktree]
```

`/deliver` §0 and §7 both call it; §7's call is the one that matters, because an hour passes in
between. The run's OWN name is safe and needs no such treatment — it is born explicit (`claude -n`),
which the titler skips. Only a name poked in from outside gets clobbered.

**`SENT=yes` is final — do not follow it with a `--resend`.** The script reads it off the run's own
transcript (the `/deliver <plan>` turn was *submitted*, not just typed onto the pane), and it has
already retried both measured hand-off failures — a held-message box, an eaten Enter — before it
answers. A resend after every launch was the ritual the old pane-grep forced (25 of 106 launches in
the week of 2026-09-15); it is no longer needed.

`SENT=unconfirmed` means the transcript still showed no plan after those retries. Do not retype it by
hand — the same script owns the recovery:

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/launch-run.sh --resend <plan-path>
```

It touches no worktree and creates no session: it checks the run's transcript first (already holding
its plan → it types nothing), otherwise answers a held-message box, and — this is the part
hand-typing gets wrong — presses **Enter alone** when the line is already sitting *unsent* in the
input box, instead of typing a second `/deliver` that queues a duplicate. Idempotent, so running it
twice is safe. Exit `72` means the session is gone (the run is dead, not stuck — dispatch it again);
`73` means still unconfirmed after the retry, so read the pane it printed.

Use it on `SENT=unconfirmed`, and on a `STALLED … was its plan ever sent?` line from the watcher —
never as a reflex after `SENT=yes`. A wave that is launched but never sent is a wave that quietly did
not run, so never report "started" on `unconfirmed`.

What the script pins, and why (so nobody "simplifies" it):

- **`CLAUDE_CONFIG_DIR` named outright in the child's command, never inherited.** `claude-work` /
  `claude-personal` are zsh functions, invisible to `sh`, `tmux`'s shell, `launchd`. An unpinned run
  lands in `~/.claude`: different auth, different agent registry, different skills, invisible to the
  watcher.
- **`tmux -L impl-<project>`, a socket per project.** The operator's default server predates the
  login session and its children come up `Not logged in`; a socket shared across projects made one
  repo's agent read another's healthy runs as strays. `<project>` comes from the git *common* dir,
  so a worktree computes the same socket as the main checkout.
- **`--permission-mode bypassPermissions`** *(supersedes acceptEdits)*: nobody watches the pane, and
  settings load at session start, so a parked prompt can never be retro-approved — allowlisting the
  tool does not rescue a parked run, and the next un-allowlisted tool parks the next one.
  `acceptEdits` auto-approves only Edit/Write/NotebookEdit, so every other tool still hits the
  permission engine. Blast radius is the worktree, not the mode: `/deliver` forbids deploy and any
  production-destructive action the plan did not authorise, and `Bash(*)` was allowlisted anyway.
- **The hand-off is typed at the TTY (`send-keys`), not a cross-session `SendMessage`.** A message
  can be *held* on a permission-mode mismatch and a held message looks exactly like a healthy idle
  session. Keystrokes cannot be held. The line carries `cockpit: <name>` — the return address
  `/deliver` §7 reports to; without it the run finishes and has nobody to tell.
- **`--remote-control` needs a TTY and cannot carry `-p`**, hence `tmux` and the post-registration
  send. It has no `--max-budget-usd`; size the wave, the watcher is the backstop.
- `claude remote-control --spawn worktree` is deliberately not used: it makes its own worktrees in
  directories this skill does not name. It also cannot attach to an already-running local session
  (`--session-id` resolves cloud/RC-registered sessions only) — choose the door before launching.

Dispatch 2-4 runs **in one wave**, not trickled: the prompt cache is warm for an hour, so a wave
reuses it while a trickle re-warms it each time. **There is no deferred path** — every dispatch
starts now; the `launchd` drainer and the queue directory are gone. "Tonight" is not an option to
offer; if the operator wants work to start later, they say so and nothing in this skill runs.

Only the `deliver` handoff skips this script (it would background an attended run): make the worktree
by hand, run the declaration's worktree-setup commands, then `claude` in the foreground inside it,
prompt and all, permission mode left alone — an attended run *should* ask.

Once delivery is confirmed, arm the death detector for that run — a pure subscription, no message, so
it costs the run nothing:

```
SendMessage({to: "impl: <parent> · <slug>", notify_when_idle: true})
```

Read what comes back as *"this run stopped talking"*, never as *"this run finished"* — §5 explains
why, with the measurement.

Then go straight to §5 — the watcher starts in this same turn.

## 5. Start the watcher — same turn as the wave, not later

Three signals reach you, and they are not interchangeable:

| Signal | What it proves | Trust it for |
|---|---|---|
| **`DELIVERED …` message from the run** (`/deliver` §7) | the run reached the end of its plan and judged its own gates | **completion** — this is the only signal that means done |
| **`notify_when_idle` notice** | the run stopped talking, or exited | **death** — go look; never read as done |
| **`watch-runs.sh` tick** | externally observable state | everything the run cannot self-report |

**Never treat idle as finished.** A session that hands work to `Workflow`, a background `Agent`, or a
background `Bash` ends its turn at once and reports *idle* while the work is still running; the idle
notice is **one-shot**, so a false fire consumes the only notice you get. `/deliver` §5 tells runs to use `Workflow` for multi-slice
plans, so this is the normal case, not an edge one. A cockpit that lands on an idle notice
squash-merges a branch still being written.

**`claude agents` is the operator's pane. Do not rebuild it, and do not narrate what it already
shows.** What it cannot do is notice on their behalf. So the moment a wave is launched, start the
watcher in this session and leave it running until the last branch lands — **unless one is already
running here**, in which case it already covers this wave too (§0b) and starting a second is pure
duplicate cost. Watch your own runs only:

Arm it as a **detached** `Bash` call — `run_in_background: true` — and end your turn:

```
CLAUDE_CONFIG_DIR=<profile> "${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/watch-runs.sh --watch --mine "<key>"
```

`<profile>` is the `CLAUDE_CONFIG_DIR` the wave was launched under (§3), as a literal path. `<key>` is
this cockpit's pairing key (`ln-de`).

**The watcher ticks; you do not.** `--watch` loops on its own clock inside the script and returns only
when the normalized finding set changes — so a wave that is merely working costs this session nothing
at all, and the harness re-invokes you the moment the picture moves. When that notification arrives:

1. Read the `WAKE <reason>` line and the findings under it.
2. Act per the prefix contract below — `PushNotification` on a new `BLOCKED`, `STALLED`, or `ORPHAN`;
   `/land` on `UNLANDED` per the plan's `## Handoff`.
3. **Re-arm it** with the same command, unless the reason was `quiet`. The state file persists across
   invocations, so re-arming while a run is still `BLOCKED` will not fire again on that same fact —
   only a genuinely new picture wakes you.

Two knobs, both rarely needed: `--interval` (seconds between ticks, default 60) and `--max-min`
(heartbeat ceiling, default 30 — it returns with `WAKE heartbeat` so a watcher can never outlive its
cockpit unnoticed). Add one `ScheduleWakeup` of ~30m as a floor the first time you arm it, so a killed
watcher cannot silently end the wave.

**Do not also start a `/loop`.** One watcher per session (§0b); a `/loop` on top of `--watch` is the
per-minute poll again, paid twice.

**`--mine` takes the pairing KEY, not a name** (`ln-de`, the part §3 puts in front of both) — so it
keeps working when a cockpit's human half is renamed. It drops a run belonging to another cockpit
outright. What it does **not** drop is anything belonging to no session: a name that does not follow
the pattern (a hand-started run), and the repo-global findings — `ORPHAN`, `FOREIGN`, and a branch
whose worktree is gone. Those are project-wide by definition and you still report them.

**Why the tick moved into the script** *(supersedes the `/loop 1m` spelling)*. The cadence was always
chosen for `BLOCKED`, not for progress — a run parked on a held-message dialog does nothing until
someone answers it, so "parked" to "noticed" is dead time on every dispatch that hits one. A one-minute
`/loop` made that gap negligible by paying a cockpit turn per minute for the life of the wave, and each
of those turns re-read the whole conversation. Measured 2026-09-22 across 7 days: **2,187 cockpit turns
and 421M cache-read tokens**, almost all of them reporting no change. `--watch` keeps the one-minute
detection and drops the per-minute turn, because the comparison that decides "is this worth waking for"
is a `sed`/`sort`/hash — it does not need a model.

One consequence worth stating: the wake rule is a **single** set comparison, and that is sufficient
because the alarm states are themselves computed from elapsed time. A run that goes silent crosses
`STALL_MIN` and a `STALLED` line *appears* — which is a set change. "Nothing is happening" and "nothing
has happened for too long" therefore arrive through the same door, and no second timer exists to get
out of sync. `STALL_MIN` stays at 15.

`watch-runs.sh` ships **next to this skill**, not in any project, so every repo the pipeline touches
gets the same watcher with no per-repo copy to drift. It discovers the repo root, trunk, and worktrees
from git, so it gives the same answer from the main checkout, from inside a worktree, or from an
unrelated repo. Two env knobs: `STALL_MIN` (silence before busy counts as stalled, default 15) and
`WT_BRANCH_PREFIX` (the branch namespace §3 creates, default `wt`).

**Name the profile in that command as a literal, and set it as well as read it.** This machine runs
more than one profile (`.claude-work`, `.claude-personal`, and the bare `~/.claude` that dispatches
nothing), each with its own `claude agents` registry and its own transcripts. Running the watcher with
the wrong `CLAUDE_CONFIG_DIR` polls a registry that has never heard of the wave, which reports a
healthy run as `FOREIGN` and a finished one as nothing at all. The old spelling here,
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, was wrong the moment the variable was unset: its fallback named
a profile with no runs in it. §3's script pins the wave to `CLAUDE_CONFIG_DIR`, so the watcher names that same path
rather than hoping to inherit it.

The *script* path is a different matter and needs nothing from you: the scripts ship in the `workflow`
plugin, and Claude Code expands the plugin-root placeholder in these commands to the plugin's directory
when it loads this skill. The profile says whose wave it is; it no longer says where the code lives.

It is one-shot and report-only — it never kills a run and never lands a branch. Its prefixes are the
contract:

| Prefix | Means | Your move |
|---|---|---|
| `RUNNING` | healthy, transcript moving | nothing — do not report it twice |
| `BLOCKED` | waiting on a prompt, with the tool named | notify; only the operator can answer it |
| `STALLED` | reports busy, silent past the threshold | notify; a run this quiet is usually wedged |
| `ORPHAN` | worktree holds work, no session drives it | notify; needs `/land` or a restart |
| `UNLANDED` | finished, or a branch whose worktree is gone | `/land` per the plan's `## Handoff` |
| `QUIET` | nothing dispatched, nothing unlanded | the watcher exits; do not re-arm |
| `FOREIGN` | work in a worktree, driven by another profile or a cloud session | nothing — not yours to land or report |

Remote Control runs register in `claude agents --json` as `kind: "interactive"` and do report
`status`, so the prefixes above still work — with one wrinkle this design introduces. An RC session is
**idle twice**: once when `/deliver` has finished, and once in the gap between launch and the send
that gives it its plan. Both look identical from the registry, so the script separates them by
whether the branch holds any work — no commits and nothing dirty reads `RUNNING  up and idle, waiting
for its plan`, and once that state outlasts `STALL_MIN` it escalates to `STALLED`, which is how you
find out a session was launched and then never sent its plan.

**Watch from the profile that dispatched** — the `CLAUDE_CONFIG_DIR` of §3. `claude agents` reads its
registry from `CLAUDE_CONFIG_DIR`, and each profile on this machine has its own runs, so a poll from
the wrong one cannot see the wave at all. The script compensates by
asking the OS — a live process whose cwd is the worktree, or a transcript under any `$HOME/.claude*`
root that moved recently — so a healthy run reads `FOREIGN` rather than a false `ORPHAN`. `RUNNING`,
`BLOCKED`, `STALLED` and `UNLANDED` still require the dispatching profile, because only its registry
carries a run's status.

Landing stays owned by `## Handoff` — the watcher reports `UNLANDED`, it does not act on it. One
decision, one owner.

When the operator asks "what is running" — or on their first message of the day — answer in plain
words, not in prefixes:

- which features are in flight, and in which worktree;
- which finished, and what each decided alone (from `## Decisions (agent-made)`);
- what is **not delivered**, per plan — the operator's next pickup;
- anything waiting on their call, and any branch that failed to land.

Only send a `PushNotification` for something that changes what they would do next: a run needs a
decision, or a branch would not land. Not for progress.

## 6. Then land

Runs are not done until `/land` has put them on `main` as one commit each. A finished run with
an unlanded branch is the failure mode this whole pipeline exists to prevent — chase it the same day.

**For `Handoff: both`, land on the run's own `DELIVERED … gates: green` verdict — nothing else.** Not
an idle notice (§5: it fires while a workflow is still running), and not a `watch-runs.sh` `UNLANDED`
line on its own, which reads the same whether the run finished or died mid-slice with commits on the
branch. `gates: RED` or `not-run` is a report to the operator, not a licence to land.

### The relay has three seams, and every one of them has failed

`/intent` → `/dispatch` → `/deliver` → `/land` is a relay across sessions, so every hop is a place
the baton gets dropped silently. All three of these are measured, not hypothetical:

| Seam | How it fails | What you do |
|---|---|---|
| dispatch → run | the Enter was eaten, so the run sat at an empty prompt holding no plan while the old pane-grep said `SENT=yes` | fixed at the source: `SENT` now comes from the run's transcript, after the script's own retry (§3). On `SENT=unconfirmed`, or a watcher `STALLED … was its plan ever sent?` → `launch-run.sh --resend <plan>` |
| run → cockpit | the run finished, but its cockpit had been **auto-re-titled** since dispatch, so the `cockpit:` name it was handed no longer resolved | fixed at the source: `cockpit-addr.sh` resolves the address from the cockpit's sessionId at send time (§3). If you still see a "couldn't find its cockpit" line, or a *stranger* session forwards you an orphaned `DELIVERED`, the run is fine — read `<worktree>/.claude/deliver-state/<slug>/verdict` and land on it |
| run → cockpit | the run finished but its `DELIVERED` message was **held** for approval and never arrived | read the pane: `tmux -L impl-<proj> capture-pane -p -t impl-<proj>-<slug> \| tail -30`. **A `DELIVERED … gates: green` line sitting in that pane IS the verdict** — it was produced by the run, and a held message is a delivery failure, not a missing judgement. Land on it |
| cockpit → land | nobody invokes `/land`, and a finished branch waits | `Handoff: both` means you land it. `UNLANDED` from the watcher after a verdict is your cue, not the operator's |

So: a run that goes quiet without a verdict **in its message channel** is a run whose pane you read.
Only if the pane holds no verdict either is it a run to inspect rather than a branch to merge.
