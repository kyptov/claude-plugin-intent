# Bootstrap a project's /deliver mechanics scripts

`/deliver` §0c stops when a project has no mechanics scripts. This is the prompt that ends that stop.
**Paste the block below into a Claude session in the project that needs them** — it is self-contained
on purpose: it states the contract, not the implementation, so the scripts come out shaped by that
project's own gates rather than copied from another repo's.

`loadnex` is the reference implementation (`.claude/scripts/deliver/`). Read it for shape if you have
it; do not copy it verbatim into a project whose gates differ.

Its sibling is **`../dispatch/BOOTSTRAP.md`**, which builds the `/dispatch` preflight. A project needs
both — each skill stops on its own missing script — and they are independent, so paste either prompt
first or both in one session.

---

```
Build this project's /deliver mechanics scripts. They are the deterministic half of the shared
/deliver skill, which refuses to run without them.

FIRST read .claude/workflow.md (the project workflow declaration). Every command, path, trunk name
and gate below comes from there — never from assumption. If the file does not exist, stop and ask me
for the gate commands, write the file, then continue.

Write three scripts, plus a small sourced lib for what they share:

  .claude/scripts/deliver/preflight.sh
  .claude/scripts/deliver/gate.sh
  .claude/scripts/deliver/report.sh
  .claude/scripts/deliver/lib.sh        (sourced, not executable)

CONTRACTS — the exit code is the interface; the skills route on it, so these numbers are fixed.

deliver/preflight.sh            run once, before the first edit
  Refuse the main checkout: compare `git rev-parse --git-dir` with `--git-common-dir`.  -> 65
  Prove the worktree is usable: dependencies installed, and whatever local env/config file the
    declaration's worktree-setup step carries in (its absence means that sync never ran).  -> 70 / 71
  Prove the test database (or whatever the integration suite needs) is actually reachable, with a
    real connection, not a port probe. Provision it if the declaration says each worktree gets its
    own — through the project's OWN provisioning command, never by hand-writing an env file.
                                                                                    -> 72 / 73
  Record a BASELINE: run the fast gates (lint, typecheck) BEFORE any edit exists and write the names
    of the ones already red to the state dir.
  0 = ready.

gate.sh --slice <id> | --full | --dry-run
  Run the declaration's gates in this order: REGENERATION first (a stale generated file makes the
  type gate lie), then lint, typecheck, any type-only gate, then tests, then any probe.
  Derive every conditional gate from the touched paths — `git diff --name-only <merge-base>...HEAD`
  plus the working tree — one branch per row of the declaration's conditional-gates table. Where a
  row is a requirement no script can judge (an authorization assertion, an audit-log entry), do the
  cheap structural check if one exists and print a NOTE saying it is structural, otherwise just NOTE.
  --slice runs the affected-only test form; --full runs the whole graph; --dry-run prints the gates
  the slice triggers and runs none.
  A failure whose gate name is in the baseline prints PRE-EXISTING and is NOT counted.
  Count real failures per slice in a state file:  first red -> 30, second -> 31 (the caller escalates
  the model), third -> 32 (a stop reason).  All green -> 0, and record the verdict for report.sh,
  keeping the --full verdict separate from a per-slice one.

report.sh <plan-path> [--shipped "<one line>"]
  Validate the plan: the sections /deliver writes must exist  -> 41, and every `## Not delivered`
  entry must carry the routing tag the declaration's debt-destinations section reads
  ([agent]/[operator] or that project's equivalent)  -> 40. An untagged entry is an item that
  disappears when the plan file is deleted; that is the whole reason this script exists.
  Refuse a verdict the run did not earn: slices green but no full-graph run  -> 44.
  Warn on an uncommitted tree (the landing step refuses one)  -> 43.
  Then print, ready to paste: the file/commit counts read off the branch, a SUMMARY: line and a
  MESSAGE: line in the shape /deliver §7 specifies.

RULES for all of them:
- macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile. Use `set -uo pipefail`.
  Nested inside `$( … )`, a case pattern needs a leading `(` — `case $x in (a|b) … ;; esac` — or
  bash 3.2 mis-parses the closing paren and dies with a syntax error.
- Output discipline: ONE line per gate on success, and only the last ~15 lines of a failing gate's
  log. Full logs go to the state dir. Nobody reads a dispatched run's pane, so every line printed is
  paid for again on every later turn of that run.
- If the project's gates need a wrapper to reach a resource (a relay, a tunnel, a VPN helper), have
  the script RE-EXEC ITSELF under that wrapper, idempotently. Wrapping the script wraps the gates and
  the regeneration steps, which are its children; passing a pre-wrapped command string does not.
- State (baseline, per-slice counters, logs, verdict) goes in one gitignored dir keyed by the branch
  slug, e.g. .claude/deliver-state/<slug>/.
- Every non-obvious line gets a comment saying WHY, in the declaration's own terms. These scripts are
  read cold by an agent that has never seen them.
- Never let a script deploy, migrate production, or edit a file the declaration marks protected.

THEN wire them up, three edits:
1. .claude/workflow.md gains a "Scripted mechanics" section: one table row per script with its exit
   codes, plus the pointer lines under whatever section lists what the generic skills read.
2. The worktree-sync allow-list (or equivalent) carries .claude/scripts/ — a dispatched run that
   finds no gate.sh stops by design, and that must not be one missing line away.
3. .gitignore: the state dir. Also ignore .claude/scripts/ if you keep the scripts untracked — an
   untracked path makes `git status --porcelain` non-empty, which is exactly how report.sh and the
   landing step both read "dirty worktree".

FINALLY prove they work, and show me the output — do not just tell me they are written:
- deliver/preflight.sh from the main checkout exits 65; from a throwaway worktree with no
  dependencies installed, 70.
- gate.sh: introduce one type error in a real package inside a throwaway worktree, then run it three
  times and show exits 30, 31, 32. Hand-write a baseline naming those gates and show the same run
  come back 0 with PRE-EXISTING.
- gate.sh --dry-run with a file touched from each conditional row, and show that each row fired.
- report.sh against a plan with an untagged entry (40), a missing section (41), and a good one.
Delete every fixture, branch and worktree you made.
```
