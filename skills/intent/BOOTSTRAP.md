# Bootstrap a project's plan-check script

`/intent` §6 asks one question that approves the plan *and* authorises the whole unattended chain
behind it. There is no `ExitPlanMode` round and no human read of the plan file, so the plan's
correctness has to be machine-checked. **Paste the block below into a Claude session in the project
that needs it.**

`loadnex` is the reference implementation (`.claude/scripts/intent/plan-check.sh`). Read it for shape
if you have it; do not copy it verbatim into a project whose plan template differs.

Siblings: **`../deliver/BOOTSTRAP.md`** (the three `/deliver` mechanics scripts) and
**`../dispatch/BOOTSTRAP.md`** (the `/dispatch` preflight). All three are independent.

Unlike those two, a missing plan-check is **not** a hard stop — `/intent` runs with the operator
present, so the check being manual is a cost, not a hazard. It is still the cheapest script of the
three to earn its place: it runs once per plan and catches defects whose next reader is an unattended
run at 3am.

---

```
Build this project's plan-check script — the one machine check on a plan contract before /intent's
final question authorises the whole unattended chain.

FIRST read .claude/workflow.md (the project workflow declaration): where plans live, which template
they follow, the canon-doc list, the branch namespace, and where the debt pool lives. Everything
below comes from there. If that file does not exist, stop and ask me, write it, then continue.
Then READ THE PLAN TEMPLATE — every check below is defined against its actual sections, not against
a generic idea of a plan.

Write one script:

  .claude/scripts/intent/plan-check.sh <plan-path> [--template <p>] [--debt <p>]
  .claude/scripts/intent/plan-check.sh <plan-path> --set-handoff <value>

It reports EVERY finding in one pass, then exits with the first code in check order — an author wants
the whole list, not one error per run.

CHECKS — the exit code is the interface:

  40  A section the template declares is missing from the plan. DERIVE the required list from the
      template file; never hard-code a second copy that can drift. Compare on the heading's leading
      words (before any parenthetical gloss) so a plan may drop the template's explanatory suffix.
  41  An unfilled template placeholder survived. Detect it by INTERSECTION: a `<…>` token present in
      both the template and the plan was copied and never filled. Do not flag every `<…>` — prose
      like "<200 chars" is legitimate. Two exclusions, both of which will otherwise fire on a
      correct plan (measure this on a real filled plan before you believe otherwise):
        - anything on an HTML-comment line — the template's append-here markers ship commented
          EXAMPLES that every plan keeps verbatim;
        - the boilerplate sections that are instructions copied into every plan and contain
          illustrative tokens nobody replaces (in loadnex: "Where it runs", "Model policy", "Gates",
          and "Handoff", which has its own check).
  20  `## Handoff` missing, not one of the template's values, or still a placeholder (a line carrying
      `<` or `|` is a placeholder, not an answer).
  42  A slice with no `- Files:` line (that line is what /dispatch's overlap test reads) or no
      `[verify]` gate (a slice with no gate cannot be checked).
  43  A `[verify]` command that positively does not resolve in this repo: an unknown package-manager
      script, or a file path that does not exist. Only a POSITIVE non-resolution fails — an
      unrecognised shape passes with a note, because a false red here costs an interview round.
      Extract the LAST backticked span after the `[verify]` marker: the first span after it is the
      `: ` separator, whose head is the shell builtin `:`, which resolves — so a naive extraction
      makes every bogus command pass, silently.
  44  A `## Canon sections` anchor that does not resolve: the doc file is missing, or the `§n` it
      names has no matching heading. Match the project's real heading style (in loadnex `## 12.`,
      `### 12.1`, `### 8a.`, `## Phase 15`), and accept a literal `§n` the doc uses to self-reference.
      Read only backticked tokens on bullet lines that look like a doc path — the section's prose
      backticks other things, and flagging those is noise.
  45  An `## Out of scope` item with no routing mark (in loadnex `[boundary]` / `[gap]`). The
      landing step routes on the mark, so an unmarked item silently disappears.
  46  The plan's slug already has a branch or a worktree. Catch it here, not at dispatch time, which
      is after the interview is over.
  0   Well-formed.
  64 usage · 65 not a git repo · 66 no such plan.

ADVISORY, never fatal: intersect the plan's `- Files:` paths with the debt pool and print the
entries that mention them, so the plan can name the debts it would close. The pool's problem is
drain, not intake, and an incidental fix that goes unrecorded is a real loss.

--set-handoff <value>: rewrite the `Auto:` line under `## Handoff` and exit. This is /intent §6's
"write the answer BEFORE you do anything else with it" — the recovery path if that turn dies, because
/dispatch then reads the file instead of asking the operator to decide twice. Validate the value.

RULES:
- macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile. Use `set -uo pipefail`. A case pattern
  nested inside `$( … )` needs a leading `(` or bash 3.2 mis-parses its closing paren.
- Beware backticks inside double-quoted strings — they are command substitution. Use single quotes
  for any message that contains one.
- A `while read` loop runs in a subshell: its findings must come back as text, not a variable.
- Read-only apart from --set-handoff. It never commits, launches, or touches source.
- Every non-obvious line gets a comment saying WHY, in the declaration's own terms.

THEN wire it up: a row in the declaration's "Scripted mechanics" table with these exit codes, a
pointer line wherever the declaration lists what the generic skills read, and .claude/scripts/
carried by the worktree-sync allow-list / ignored, consistent with the other mechanics scripts.

FINALLY prove it works, and show me the output — do not just tell me it is written. Fill a copy of
the template into a REAL well-formed plan first and show it passing clean (a check suite that has
never returned 0 is not calibrated). Then break one thing at a time from that good plan and show
each code: 40, 41, 20, 42, 43 (both an unknown script AND a missing file path), 44, 45, 46, plus
--set-handoff writing the line and the debt advisory firing without changing the exit code.
Delete every fixture and branch you made.
```
