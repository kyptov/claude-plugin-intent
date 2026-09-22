---
name: land
description: Merge a finished worktree branch into the trunk as exactly one commit — squash, rebase onto origin, re-run the gates, fast-forward, push, remove the worktree, delete the branch — retrying when another run lands first and never abandoning a branch silently. Invoked by /dispatch when the plan's Handoff is "both", or by the operator to land, merge, or clean up a worktree. Not for planning (/intent) or implementing (/deliver).
argument-hint: worktree path or branch name; omit to land every finished worktree in turn
---

# Land a worktree onto main

Target: $ARGUMENTS

## 0. Read the project's declaration first

Read **`.claude/workflow.md`** in the project root: trunk branch, gate commands and their traps, plan
locations, model policy, deploy authority, canon docs. Everything project-specific comes from there,
never from assumption. If it is missing, ask the operator for the gate commands once, write the file,
then continue — never guess gates, because a wrong gate makes every downstream green meaningless.

Parallel worktrees without an enforced land step lose finished work: a complete, tested branch can
sit unmerged indefinitely, because nothing forces the merge and no session list shows it.

Invariants: `main` stays **linear**, gets **one commit per feature**, and **no branch is ever left
behind quietly.**

---

## 1. What is a script and what is judgment

Everything mechanical about a landing — the land lock, the squash, the rebase→gates→fast-forward
loop, the push, killing the run's `tmux` session, the per-worktree teardown, removing the worktree
and branch, releasing the lock — is **one script next to this skill**, `land.sh`. You run it once,
after the two judgment steps below (§2 the sweep, §3 the message). Never re-derive that sequence by
hand.

## 2. Sweep the plan into the debt files — before the squash

The plan file is about to be deleted, and everything the run did not do lives in it. **Move that out
first, in the worktree, so the same commit that lands the feature also files what it left behind.**

A shipped plan's leftovers (an unrun production backfill, a named deferral) die with the plan file
unless something files them first. `/deliver` cannot do this — it is forbidden to touch the debt pool
mid-run, correctly — so if `/land` does not do it, nothing does.

`.claude/workflow.md` names the two destinations (a "Debt destinations" section). Read it; do not
guess the paths. If it names none, put both lists at the end of the plan's own commit message instead
and say so in the report — never drop them.

**Route each item mechanically, do not re-judge it:**

| Item | Goes to |
|---|---|
| `## Not delivered` entry an agent could do given a plan | the debt pool, in the closest-matching subsection |
| `## Not delivered` entry only a human can do — a production migration, a production backfill, a deploy, an on-device or in-browser check, an external-portal action, a decision owed | the operator queue |
| `## Out of scope` entry that is **unbuilt work someone will want** | the debt pool |
| `## Out of scope` entry that is **a boundary, not a gap** — version-deferred by design, another doc's scope, "do not helpfully add this" | dropped; it was scope, never debt |
| `## Decisions (agent-made)` | already carried by the squash commit body (§3) — do not duplicate |

Each filed item gets: the date, one sentence of what and why it matters, and `*(swept from the
retired <slug> plan)*` so a reader can find the commit. **Verify before you file** — an item deferred
weeks ago is often already done by later work, and filing a resolved item is worse than filing
nothing because it makes the pool untrustworthy. One read-only check is enough; if it is already
done, say so in the report and file nothing.

Then `git rm` the plan file, unless `.claude/workflow.md` names it as deliberately kept.

**Before you delete it, check nothing in the tree points at it:**
`grep -rIl --exclude-dir=node_modules '<slug>' .` — a comment or migration header citing a plan path
becomes a dead link the moment the plan is gone. Repoint each hit at the landing commit hash or the
canon doc, in this same commit.

Two runs landing at once both append here, so a conflict on the debt files is expected and always
resolves the same way: **take both sides.** Never drop the other run's items to make a rebase clean.

## 3. Write the squash message

A conventional commit (scopes per the project's conventions) in a temp file:
- subject = the capability from the plan's `# <title>`, in product terms;
- body = the `## Decisions (agent-made)` entries, one line each, so the reasoning survives in
  `git log` after the plan file is deleted;
- footer = `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

Commit the §2 sweep in the worktree first — `land.sh` refuses a dirty worktree, and the sweep must
ride inside the squash.

## 4. Run it

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/land/land.sh <worktree-path> --message-file <msg> \
  --gates "<gate commands from .claude/workflow.md>" \
  --extra-gate "<each conditional gate from the declaration's table that the plan triggered>" \
  --teardown "<per-worktree teardown command from workflow.md, if it names one>" \
  --lock-wait "<minutes, only if the declaration names one>"
```

**Run it detached — `Bash` with `run_in_background: true`.** It can wait for another landing *and
then* run the full gates, which outlasts a foreground tool call; a killed tool call is also the one
thing that can strand the lock (the script releases it on every other exit).

`--gates` is required and is the declaration's full gate line; trunk defaults to `origin/HEAD`, 3
attempts, branch namespace `WT_BRANCH_PREFIX` (default `wt`). The
script: takes `.claude/land.lock`, **waiting up to `--lock-wait` minutes (default 25) when another
landing holds it** — two landings overlapping in a wave is the normal case, so the second one queues
instead of bouncing back to you; it takes a lock over at once when its owning process is gone.
Exit 10 means the wait ran out, which is a landing that is stuck rather than busy — report it,
do not re-run on a loop. A project whose gates are slow says so in its declaration (ml-billing's
8-16 minute suite needs `--lock-wait 50`: three rebase attempts each re-run them). Then it squashes with
`reset --soft <merge-base>` + one commit (exit 24 on an empty diff — the run delivered nothing,
report that rather than landing a no-op); then up to 3 × { `git fetch`, `git rebase origin/<trunk>`,
gates, `merge --ff-only` in the main checkout } — **re-running the gates after every rebase**,
because `main` moved and the previous green described a tree that no longer exists; then pushes;
then **kills the run's session first, tears down second, removes the directory third** (a live
session in a removed directory fails its Stop hook every turn, and the teardown derives its target
from the worktree's own path). Teardown failure warns and continues: it must never block a green land. Last line on
success: `LANDED <hash> <subject>`.

## 5. Read the exit code, then confirm

| Exit | Meaning | Your move |
|---|---|---|
| 0 | landed and pushed | confirm with `ListAgents` + `git worktree list` that the `impl:` row and the worktree are gone, then report the hash and what landed in product terms |
| 20 | rebase conflict; branch + worktree untouched | §6 |
| 21 | gates red after rebase | §6 |
| 22 | push refused | §6 (never `--force`) |
| 23 | fast-forward refused three times | §6 — `main` is moving faster than the gates; try once more, then §6 |
| 24 | empty squash | report; nothing to land |
| 10 | the script already waited `--lock-wait` minutes and the lock did not clear | report it: a landing held that long is stuck, not busy. Do not re-run on a loop, and never remove a lock by hand while its process is alive |

**Do not deploy.** That word belongs to the operator.

## 6. When it does not land

On a rebase conflict, red gates after rebase, or a 3rd refused fast-forward:

1. Re-attempt that step once at the declaration's escalation model/effort — conflicts are exactly the case where the cheap model
   is a false economy, and this path is rare enough that the cost is noise.
2. If it still fails: **leave the branch and the worktree exactly as they are.** Release the lock.
   Write a one-paragraph reason to the branch-triage file the declaration names (branch, what
   conflicts, what a human needs to decide) and send one `PushNotification` under 200 characters.

Never `git push --force`, never delete an unmerged branch, never leave a branch unmentioned. A branch
that cannot land must be **loud**, because the alternative is a finished feature nobody knows exists.

## 7. After a landing, the next dispatch guards itself

Nothing to do here by hand: `/dispatch` §1 runs the project's dispatch preflight per plan, which
lists every unlanded branch and **blocks only when one overlaps the next plan's files** (its exit
12).

What is worth doing after a green land is confirming the pair the landing removes — the `impl:` row
is gone from `ListAgents` and the worktree is gone from `git worktree list` (§5, exit 0). A branch
that survives its own landing is the backlog this skill exists to prevent.
