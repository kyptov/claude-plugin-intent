# Bootstrap a project's dispatch preflight

`/dispatch` §1 stops when a project has no dispatch preflight. This is the prompt that ends that
stop. **Paste the block below into a Claude session in the project that needs it** — it states the
contract, not the implementation, so the script comes out shaped by that project's own locks, trunk
and plan template rather than copied from another repo's.

`loadnex` is the reference implementation (`.claude/scripts/dispatch/preflight.sh`). Read it for shape
if you have it; do not copy it verbatim into a project whose lock files or plan template differ.

Its sibling is **`../deliver/BOOTSTRAP.md`**, which builds the three `/deliver` mechanics scripts.
A project needs both — each skill stops on its own missing script — and they are independent, so
paste either prompt first or both in one session.

---

```
Build this project's /dispatch preflight script — the deterministic half of the shared /dispatch
skill, which refuses to dispatch without it.

FIRST read .claude/workflow.md (the project workflow declaration): the trunk name, the branch
namespace, where plans live and which template they follow, and any lock or lease files this project
keeps. Everything below comes from there — never from assumption. If that file does not exist, stop
and ask me for those facts, write the file, then continue.

Write one script:

  .claude/scripts/dispatch/preflight.sh <plan-path> [--self <session-id>]

CONTRACT — the exit code is the interface; the skill routes on it, so these numbers are fixed.

  10  A landing is in flight (this project's land lock, if it has one).
  11  The main-checkout edit lease is held by ANOTHER session and is still fresh (the declaration or
      the guard hook names the idle threshold; default 45 minutes). EXCLUDE the caller's own lease —
      resolve the caller's session id from --self, else from CLAUDE_PID via
      $CLAUDE_CONFIG_DIR/sessions/<pid>.json. A cockpit blocked by its own lease is a false stop.
      Print the holder and the idle minutes: staleness must be computed, not eyeballed.
      If this project has no such lease file, say so and skip — do not invent one.
  13  The main checkout is dirty. A worktree branches from the trunk, so uncommitted work here would
      be silently excluded from the run AND left behind. List the paths.
  20  `## Handoff` is missing or unrecognised. A line still carrying `<` or `|` is a TEMPLATE
      PLACEHOLDER, not an answer, and must be rejected the same as a missing one. Valid values are
      whatever the plan template lists (both | dispatch | deliver | nothing).
  12  An unlanded branch OVERLAPS this plan's files. This is the part with the real value, and it is
      a set intersection, not a judgement:
        - the plan's paths: the template says where — a `- Files:` line per slice, in backticks, or
          that project's equivalent. Skip placeholder tokens (anything starting with `<`).
        - each unlanded branch: every ref under the branch namespace that is ahead of the trunk, and
          `git diff --name-only <trunk>..<branch>` for each.
        - overlap = exact path equality, or either path is a directory prefix of the other.
      An overlapping branch BLOCKS (12) — two runs editing one file is the interleaving the whole
      pipeline exists to prevent. A non-overlapping unlanded branch is REPORTED and does NOT block;
      it used to, and blocking a wave over an unrelated branch is a real cost.
      If the plan names no paths at all, print a WARN saying the test cannot run, report every
      unlanded branch, and block nothing.
  0   Clear to dispatch. Print the handoff value on the way through — the skill reads it from here
      rather than re-parsing the plan.
  64 usage · 65 not a git repo · 66 no such plan.

Check them in that order, cheapest first, and print one PASS/BLOCKED line per check so the pane
reads as a checklist.

RULES:
- macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile. Use `set -uo pipefail`.
  Nested inside `$( … )`, a case pattern needs a leading `(` — `case $x in (a|b) … ;; esac` — or
  bash 3.2 mis-parses the closing paren and dies with a syntax error. The overlap loop hits this.
- Resolve the repo from the git COMMON dir, not `--show-toplevel`, so the script gives the same
  answer called from a worktree as from the main checkout.
- A `while read` loop runs in a subshell, so its verdict cannot reach the caller as a variable —
  capture its output and decide from the text.
- Every non-obvious line gets a comment saying WHY, in the declaration's own terms. This script is
  read cold by an agent that has never seen it.
- Read-only: it inspects, it never writes, locks, commits or launches anything.

THEN wire it up:
1. .claude/workflow.md gains a row for it in the "Scripted mechanics" section (create the section if
   the /deliver bootstrap has not already), with its exit codes, plus a pointer line under whatever
   section lists what the generic skills read.
2. The worktree-sync allow-list carries .claude/scripts/ if it does not already.
3. .gitignore it alongside the other mechanics scripts if you keep them untracked — an untracked
   path makes `git status --porcelain` non-empty, which is how the dirty check above (13) and the
   landing step both read "dirty worktree", so an untracked script would block on itself.

FINALLY prove it works, and show me the output — do not just tell me it is written:
- a dirty main checkout -> 13;
- the plan template's placeholder Handoff -> 20, and a real `Auto: **dispatch**` -> passes;
- an unlanded branch touching a path the plan names -> 12, and one touching nothing it names -> 0
  with the branch reported. Build that fixture branch with plumbing — `git commit-tree` against a
  temp `GIT_INDEX_FILE` — so the working tree is never touched.
Delete every fixture and branch you made.
```
