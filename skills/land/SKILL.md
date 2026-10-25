---
name: land
description: Merge a finished worktree branch into the trunk as exactly one commit — squash, rebase onto origin, re-run the gates, fast-forward, push, remove the worktree, delete the branch — retrying when another run lands first and never abandoning a branch silently. Invoked by /dispatch when the plan's Handoff is "ship" or "both" (ship = it also runs the deploy commands after the landing), or by the operator to land, merge, or clean up a worktree. Not for planning (/intent) or implementing (/deliver).
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

A landing is waiting, a script and an exit code; the one step that needs thinking — §6's conflict
re-attempt — runs in a nested `Agent` at the declaration's escalation model. (A `model:` line in this
frontmatter would not make the landing cheaper: the harness runs a skill turn on the session's
model, measured 2026-10-25 — see `/dispatch` §0.)

---

## 1. What is a script and what is judgment

Everything mechanical about a landing — the land lock, the squash, the rebase→gates→fast-forward
loop, the push, the per-worktree teardown, removing the worktree and branch, releasing the lock — is
**one script next to this skill**, `land.sh`. You run it once, after the two judgment steps below (§2
the sweep, §3 the message). Never re-derive that sequence by hand.

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

**If the declaration names a debt *intake* directory, the debt-pool items never touch the pool
file.** Write them as one new file, `<intake dir>/<slug>.md`, grouped under the pool subsection each
belongs in:

```markdown
# Swept from the retired <slug> plan

## <pool subsection, exactly as the pool heads it>

- <item, in the pool's own item format>
```

The file name is this plan's slug, so no other landing can ever write it, and `/debt-review` folds it
into the pool later. The operator queue is unaffected — it is still edited in place, because a human
action has to be visible before the next deploy, not at the next review.

Each filed item gets: the date, one sentence of what and why it matters, and `*(swept from the
retired <slug> plan)*` so a reader can find the commit. **Verify before you file** — an item deferred
weeks ago is often already done by later work, and filing a resolved item is worse than filing
nothing because it makes the pool untrustworthy. One read-only check is enough; if it is already
done, say so in the report and file nothing.

**Close what the plan fixed, in the same file.** A plan names the pool items its slices fix
(`/intent` writes them as the plan's *closes debt* list). Verify each one read-only against the
worktree; for every one the code now resolves, add it under a `## Closed by this landing` heading in
the same intake file — its pool subsection and verbatim bold title, one per line. `/debt-review`
deletes those from the pool when it folds the file in. With no intake directory, list them in the
commit body instead; `/land` still never deletes a pool line itself.

**Update the goal the plan serves.** If the plan names a goal from the declaration's goals file,
rewrite that goal's `Status:` line to what is true once this lands (present tense, one line). Never
delete the goal — only the operator closes a goal, through `/next`.

Then `git rm` the plan file, unless `.claude/workflow.md` names it as deliberately kept.

**Before you delete it, check nothing in the tree points at it:**
`grep -rIl --exclude-dir=node_modules '<slug>' .` — a comment or migration header citing a plan path
becomes a dead link the moment the plan is gone. Repoint each hit at the landing commit hash or the
canon doc, in this same commit.

Two runs landing at once both append to any ledger edited in place (the operator queue always, the
pool when there is no intake directory), so a conflict there is expected and always resolves the
same way: **take both sides.** Never drop the other run's items to make a rebase clean.

## 3. Write the squash message

A conventional commit (scopes per the project's conventions) in a temp file:
- subject = the capability from the plan's `# <title>`, in product terms;
- body = the `## Decisions (agent-made)` entries, one line each, so the reasoning survives in
  `git log` after the plan file is deleted;
- footer = a `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer naming the model you are
  running as.

Commit the §2 sweep in the worktree first — `land.sh` refuses a dirty worktree, and the sweep must
ride inside the squash.

## 4. Run it

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/land/land.sh <worktree-path> --message-file <msg> \
  --gates "<gate commands from .claude/workflow.md>" \
  --extra-gate "<each conditional gate from the declaration's table that the plan triggered>" \
  --teardown "<per-worktree teardown command from workflow.md, if it names one>" \
  --refresh "<post-rebase refresh command from workflow.md, if it names one>" \
  --lock-wait "<minutes, only if the declaration names one>"
```

**Run it detached — `Bash` with `run_in_background: true`.** It can wait for another landing *and
then* run the full gates, which outlasts a foreground tool call; a killed tool call is also the one
thing that can strand the lock (the script releases it on every other exit).

`--gates` is required and is the declaration's full gate line; trunk defaults to `origin/HEAD`, 3
attempts. Without `--teardown`, the project's `.claude/scripts/dispatch/worktree-teardown.sh` runs when
it exists — the counterpart of the setup script the worktree hook ran, so pass `--teardown` only for a
project that declares some other command. Likewise without `--refresh`, the project's
`.claude/scripts/dispatch/worktree-refresh.sh <worktree>` runs after every successful rebase and
before the gates, when it exists — the worktree was provisioned for the base it was dispatched from,
and only the project knows what a new base needs (re-migrate its database, re-run codegen,
reinstall). The script: takes `.claude/land.lock`, **polling every 30 s for up to `--lock-wait`
minutes (default `LAND_LOCK_WAIT_MINUTES`, else 30) while a live landing holds it** — the holder is
a landing that finishes in 10–20 minutes, so the second one queues instead of bouncing back to you.
It prints the holder's branch and pid once, then nothing until it acquires the lock or gives up; it
takes a lock over at once when its owning process is gone. Waiting is not yours to manage: do not
sleep, poll or re-run around it, and do not ask `wait-for.sh` about the lock — a landing waits on
nothing, so the land lock never closes a wait cycle. A project whose gates are slow says so in its
declaration (a 15-minute suite needs about `--lock-wait 50`: three rebase attempts each re-run it).
Then it squashes with `reset --soft <merge-base>` + one commit (exit 24 on an empty diff — the run
delivered nothing, report that rather than landing a no-op); then up to 3 × { `git fetch`,
`git rebase origin/<trunk>`, refresh, gates, `merge --ff-only` in the main checkout } —
**re-running the gates after every rebase**, because `main` moved and the previous green described a
tree that no longer exists; then pushes;
then **tears down first and removes the directory second** (the teardown derives its target — a
database, a port — from the worktree's own path). Teardown failure warns and continues: it must never
block a green land. Last line on success: `LANDED <hash> <subject>`.

## 5. Read the exit code, then confirm

| Exit | Meaning | Your move |
|---|---|---|
| 0 | landed and pushed | confirm with `git worktree list` that the worktree is gone, then report the hash and what landed in product terms |
| 20 | rebase conflict; branch + worktree untouched | §6 |
| 21 | the post-rebase refresh failed, or the gates are red after rebase | §6 |
| 22 | push refused | §6 (never `--force`) |
| 23 | fast-forward refused three times | §6 — `main` is moving faster than the gates; try once more, then §6 |
| 24 | empty squash | report; nothing to land |
| 10 | the script queued on the land lock — 30 s polls, holder printed once — for `--lock-wait` minutes and it did not clear | report it: a landing held that long is stuck, not busy. Do not re-run on a loop, and never remove a lock by hand while its process is alive |
| 26 | uncommitted paths in the main checkout refused the fast-forward; the branch is rebased, green, and kept | §5a, resource `dirty-checkout` |

### 5a. Blocked by another session

A landing needs exactly two things from the rest of the repo: the land lock, which `land.sh` queues
for on its own, and a main checkout whose uncommitted paths do not stand in the fast-forward's way
(exit 26). **The main-checkout lease is not one of them** — `land.sh` neither takes nor needs it, so
another session's lease never blocks a landing; do not wait on it.

When exit 26 says another session's paths are in the way, ask the plugin's wait-for helper, which
records the wait and checks whether that session is in turn waiting on this one:

```sh
"${CLAUDE_PLUGIN_ROOT}"/skills/dispatch/wait-for.sh check --resource dirty-checkout \
  [--lease "<the declaration's main-checkout lease file, if it names one>"]
```

**Never ask the operator to make this landing wait on another session; the script decides.** Route
on its `VERDICT` line exactly as `/dispatch` §1a does: `WAIT` → run its `WAIT-CMD` detached and end
the turn, re-running `land.sh` when it ends `CLEAR`; `YIELD` → report `yielded to <session> to break
a wait cycle` with the paths it lists, and leave the branch for the next `/land`; `FIX` → the paths
are this session's own or nobody's: report them for the operator to commit or stash. None of these
is a question, and none touches the branch: it stays rebased and green.

**Do not deploy on your own.** The deploy word belongs to the operator; they give it either in the
plan (`## Handoff: ship`, the `/intent` default) or to §8's question (`both`).

### 5b. Tell the operator — one line per landing

When `land.sh` has exited and you have settled §5/§6, send one `PushNotification` and print the same
line in the reply — the operator should never have to ask whether something landed:

- exit 0 → `<slug>: landed <short hash>`
- anything else, after §6 → `<slug>: not landed — exit <code> — <what it needs, a few words>`

One per landing, never for a step in between; a no-argument `/land` sends one per branch. §8's
question still follows a green landing.

## 6. When it does not land

### 6a. A red that is the trunk's, not the branch's — a policy, never a question

Exit 21 with red gates is first a question of **whose red it is**. Measured over the week of
2026-10-19: every "trunk is red on X, land anyway?" question the cockpit asked, the operator answered
the same way — land, and deal with X separately. So decide it:

1. Name the failing test or check from the gate output.
2. It is **the trunk's red** when both hold: the branch's squashed diff touches neither the failing
   test's file nor the source it exercises (read the test's imports), **and** the same command is red
   at the trunk tip in the main checkout (run just that test there — never the whole gate — and
   never edit the main checkout to find out).
3. Then: if the fix is a few lines (a fixture, a stale snapshot, a date), fix it **on the trunk in the
   main checkout** as its own commit — a `fix` in the project's commit style, the one commit this
   skill may make outside a landing — and re-run `land.sh`; the rebase picks it up. If it is more
   than that, re-run `land.sh` with that one command removed from `--gates` / `--extra-gate`,
   file the red as a `[READY|<date>]` item in the debt intake (§2's format, source: this landing),
   and say so in §5b's line: `<slug>: landed <hash> over trunk's red <test> — filed`.
4. A red the branch **does** touch, or one you cannot prove at the trunk tip, is the branch's: §6b.

### 6b. The branch's own red, a conflict, or a refused fast-forward

On a rebase conflict, red gates after rebase that §6a could not attribute to the trunk, or a 3rd
refused fast-forward:

1. Re-attempt that step once at the declaration's escalation model/effort — a foreground `Agent`
   with that `model` and `effort`, handed the worktree, the exit and its output. Conflicts are
   exactly the case where the cheap model is a false economy, and this path is rare enough that the
   cost is noise.
2. If it still fails: **leave the branch and the worktree exactly as they are.** Release the lock.
   Write a one-paragraph reason to the branch-triage file the declaration names (branch, what
   conflicts, what a human needs to decide); §5b's line is the notification.

Never `git push --force`, never delete an unmerged branch, never leave a branch unmentioned. A branch
that cannot land must be **loud**, because the alternative is a finished feature nobody knows exists.

## 7. After a landing, the next dispatch guards itself

Nothing to do here by hand: `/dispatch` §1 runs the project's dispatch preflight per plan, which
lists every unlanded branch and **blocks only when one overlaps the next plan's files** (its exit
12).

What is worth doing after a green land is confirming what the landing removes — the worktree is gone
from `git worktree list` and the branch from `git branch` (§5, exit 0). A branch that survives its own
landing is the backlog this skill exists to prevent.

## 8. Ship — the last thing you do

A landing that ends in a report leaves nothing on production and nothing flagging it. What happens
next is decided by the plan's `## Handoff`, read from the plan file **before** §2's sweep deletes it:

### 8a. `ship` — run the deploy commands, no question

When the declaration lists deploy commands and at least one landing exited 0, run them **once,
after the last landing you have in hand in this turn** (a no-argument `/land` lands several; a wave
whose runs land minutes apart ships once at the end, and a run still building never holds the
ship). Run the declaration's routine deploy command from the main checkout, in the background,
with the target the landed diffs need — the declaration's "Deploy" section says how targets map to
paths; when it does not, run the default target. A landing that touches nothing the deploy ships
(mobile-only, docs-only) ships nothing: say so.

Read the command's exit code, then:

- shipped → one `PushNotification` and the same line in the reply: `shipped <hash> — <targets>`;
- it stopped for a decision the script itself refuses to make (the declaration's exit codes for a
  pending production migration or a host-env change) → **this is the one question**: a single
  `AskUserQuestion`, header `Ship`, carrying the script's own words (what is pending, by name) and
  offering `Approve and re-run` (first) / `Hold`. The operator's Approve is the word for that
  specific item; re-run with the flag the script names. Never pass an approval flag unasked;
- any other non-zero exit (a precondition, a red gate, a failed deploy or verify) → full output in
  the report, one `PushNotification` `<slug>: not shipped — exit <code> — <last line>`; do not
  retry and roll nothing back on your own.

A `/land` running inside a background `/dispatch` subagent has no operator for the question above:
it ships on a clean exit and ends with its report on anything else.

**Then the Done marker — the last call of the turn, in every outcome above.** One
`AskUserQuestion`, header `Done`, question `<slug>: landed <hash> — shipped <targets>` (or
`— nothing to ship` / `— not shipped: exit <code>`), one line per landing when there were several,
options **OK** (first) / **Something's off** (free text). It decides nothing: the ship has already
happened, so an answer that comes tomorrow costs nothing. It exists because a question is what marks
a session as *finished and waiting for you* in the app and triggers its notification — a reply that
ends in prose looks the same as a cockpit mid-wait on a run (the operator used the old "Deploy?" as
exactly this marker). Skip it only inside a background `/dispatch` subagent, where nobody answers.

### 8b. `both` — ask "Deploy?"

For `both` (the operator chose to ship by hand), end with one `AskUserQuestion` instead — it
notifies the operator, and their answer is the deploy word.

Ask it once, after the last landing of this run, when:

- at least one landing exited 0, and
- the declaration lists deploy commands, and
- the session is interactive — a `/land` running inside a background `/dispatch` subagent has no
  operator to answer; it ends with its report.

The question carries the report so the notification reads on its own:

- question: `Landed <hash> <subject>. Deploy?` — one line per landing when there were several, plus
  any operator-queue items this sweep filed that must happen before a deploy (a production
  migration, a backfill), named in a few words each;
- header: `Deploy`;
- options: **Yes** — run the declaration's deploy commands in order from the main checkout and
  report each one's outcome; **Not now** — stop.

When the question names items owed before deploy, word it `… Deploy? Owed first: <items>` — a Yes
then means the operator has done them. A deploy command that fails gets its full
output in the report; do not retry it or roll anything back on your own.
