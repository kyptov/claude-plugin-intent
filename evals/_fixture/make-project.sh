#!/bin/bash
# Shared scaffold for the eval cases: a small project, `demo`, declared for the workflow skills the
# way a real project is, with one approved plan (docs/plans/duration-format.md).
#
#   make-project.sh main       the workspace is the MAIN checkout, on `main` (cockpit cases)
#   make-project.sh worktree   the workspace is the run's WORKTREE on wt/duration-format (deliver)
#   make-project.sh delivered  main checkout, plus the finished run at ../demo-wt-duration-format (land)
#
# Called from a case's own scaffold script with the workspace as cwd. The mechanics scripts are
# stubs: runs have no Bash, so they only need to exist — every case's prompt supplies their output.
set -euo pipefail
mode=${1:-main}
ws=$PWD

# The repo lives in the workspace for `main`, or beside it for `worktree` (the workspace then
# becomes a real linked worktree, so .git is a file and git-dir != common-dir, as in a real run).
if [ "$mode" = worktree ]; then repo="$(dirname "$ws")/demo"; else repo=$ws; fi
mkdir -p "$repo" && cd "$repo"
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval

mkdir -p .claude/scripts/{deliver,dispatch,intent} docs/plans docs/planning src

cat > CLAUDE.md <<'EOF'
# demo — binding rules

- TypeScript, ESM, no default exports. Tests beside the file as `*.test.ts` (vitest).
- Durations are stored and passed around as whole seconds (`number`). Formatting happens only at the
  display edge, in `src/duration.ts`.
- Comments cite a canon doc section or a commit, never a plan path.
EOF

cat > package.json <<'EOF'
{
  "name": "demo",
  "private": true,
  "type": "module",
  "scripts": {
    "check": "npm run lint && npm run typecheck && npm test",
    "lint": "biome check .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  }
}
EOF

cat > src/duration.ts <<'EOF'
// Display formatting for durations. Canon: docs/time.md §1.
export function formatSeconds(seconds: number): string {
  return `${seconds}s`;
}
EOF

cat > src/run-card.ts <<'EOF'
import { formatSeconds } from "./duration.js";

export function runCardLine(name: string, seconds: number): string {
  return `${name} — ${formatSeconds(seconds)}`;
}
EOF

cat > docs/time.md <<'EOF'
# Time and durations

## 1. Display rules

Durations reach the UI as whole seconds and are formatted only by `src/duration.ts`. Today every
surface prints raw seconds (`3900s`), which operators read as noise.

## 2. Storage

Seconds, integer, never negative. No change to storage is planned.
EOF

cat > docs/planning/debt.md <<'EOF'
# Debt pool

## §1 Display
EOF
printf '# Operator queue\n' > docs/planning/operator-queue.md
printf '# Branch triage\n' > docs/planning/branch-triage.md

cat > .claude/workflow.md <<'EOF'
# Workflow declaration — demo

Project inputs for the generic workflow skills (`intent` → `dispatch` → `deliver` → `land`, plus
`debt-review`). `CLAUDE.md` is the binding rulebook and wins on any rule.

## Trunk and remote

`main` · `origin git@github.com:example/demo.git` · linear history, one commit per feature.

## Gates

`npm run check` is the whole-repo gate (lint, typecheck, tests). Nothing needs a database or network.

## Scripted mechanics — `/deliver` runs these, never hand-assembled gates

| Command | Owns | Exit codes |
|---|---|---|
| `deliver/preflight.sh` | main-checkout refusal, install present, baseline | `0` ready · `65` main checkout · `70` not installed |
| `deliver/gate.sh --slice <id>` / `--full` | the gates from touched paths; per-slice failure counting | `0` green · `30` first red · `31` second → escalate · `32` third → stop |
| `deliver/report.sh <plan>` | `## Decisions (agent-made)` + `## Not delivered` present and tagged; prints the cockpit line | `0` · `40` untagged · `41` missing section |
| `intent/plan-check.sh <plan>` | sections vs template, placeholders, slice `- Files:` + `[verify]`, canon anchors, `## Out of scope` marks, slug collision; `--set-handoff <v>` | `0` · `20` Handoff · `40` section · `41` placeholder · `42` slice · `43` verify · `44` anchor · `45` scope mark · `46` slug taken |
| `dispatch/preflight.sh <plan>` | `land.lock`, clean main checkout, `## Handoff`, overlap with unlanded `wt/*` | `0` · `10` land.lock · `12` overlap · `13` dirty · `20` Handoff |

All under `.claude/scripts/`.

## Plans

`docs/plans/<slug>.md`, tracked, from `docs/plans/_plan-template.md`.

## What the generic skills read from here

- **Binding rules:** `CLAUDE.md`.
- **Users** (for `/intent`'s plain-words questions): the operator watching runs on the dashboard,
  and a teammate reading a shared run link.
- **Worktree setup:** `--install "npm ci"`. No sync step.
- **Branch namespace:** `wt/<slug>`. **Session tag:** `dm` (`launch-run.sh --tag dm`).
- **Deploy commands** (never run by `/deliver` or `/land`): `npm run deploy`.
- **Branch triage file:** `docs/planning/branch-triage.md`.

## Model policy

Implementation `opus` / `medium`; escalate a slice to `opus` / `high` after two failed gate
cycles. Interview, plan authoring, `/land` conflict resolution: `opus` / `high`.

## Canon docs

`docs/time.md` (durations, §1–§2). Plan anchors: `doc §<n>`.

## Debt destinations (read by `/land`)

- **Debt pool** → `docs/planning/debt.md`, subsections `§1`…, each item dated.
- **Operator queue** → `docs/planning/operator-queue.md`.
- **Kept plans** (never `git rm`): `docs/plans/_plan-template.md`.
EOF

for s in deliver/preflight deliver/gate deliver/report intent/plan-check dispatch/preflight; do
  printf '#!/bin/bash\n# stub for evals: the case prompt supplies this script'"'"'s output\nexit 0\n' > ".claude/scripts/$s.sh"
  chmod +x ".claude/scripts/$s.sh"
done

cat > docs/plans/_plan-template.md <<'EOF'
# <capability, in plain words>

> Contract file. `/intent` writes it; `/deliver` executes it; `/land` merges the result, sweeps the
> two sections at the bottom into the debt destinations, and deletes this file in the same commit.

## Context

Why this exists: the problem, what prompted it, the intended outcome. Two paragraphs maximum.

## Intent (the one thing that must be true when this is done)

<one sentence, in the user's own terms — this is what the executor optimizes for when a fork appears>

## Your calls (settled with the operator — do not reopen)

- **<question>** → <answer, verbatim where the operator used their own words>

## Agent's calls (resolve during execution, never escalate)

- <named fork the executor is expected to decide alone, with the criterion to decide by>

## Canon sections (read these, and only these, before the first slice)

- `<doc path> §<n>` — <why this section governs a slice below>

## Where it runs

**A worktree, always** — `wt/<slug>`, created by `/dispatch`, squashed onto the trunk by `/land`.

## Model policy

Implementation: `opus` / `medium`. Escalate a slice to `opus` / `high` after 2 failed gate cycles.

## Handoff (answered by the operator as the last question of `/intent`)

Auto: **<nothing | dispatch | deliver | both>**

## Slices

Each slice is one user-observable capability, ends in a `[verify]` gate that is a real repo command,
and touches ~2-3 files.

### S1 — <name>

- Files: `<path>`, `<path>`
- Do: <what changes>
- `[verify]`: `<exact command>`

## Gates (every slice, non-negotiable)

`.claude/scripts/deliver/gate.sh --slice <id>` per slice, `--full` once at the end.

## Out of scope

Mark each one: `[boundary]` = excluded by design, dies with this plan · `[gap]` = real unbuilt work,
filed into the debt pool when this lands.

- `[boundary]` <thing deliberately excluded, so the executor does not "helpfully" add it>
- `[gap]` <thing someone will want, just not in this run>

## Decisions (agent-made)

<!-- /deliver appends here. One entry per fork it resolved alone. -->
<!-- - **<what>** — why: <reason>. Reverse by: <how>. -->

## Not delivered

Tag every entry `[agent]` or `[operator]`.

<!-- /deliver appends here at the end. -->
EOF

# The approved plan the dispatch/deliver/land cases act on. Deliberately silent on two forks
# (under a minute, a day or more) so /deliver has something real to decide alone.
cat > docs/plans/duration-format.md <<'EOF'
# Run durations read as hours and minutes

> Contract file. `/intent` writes it; `/deliver` executes it; `/land` merges the result, sweeps the
> two sections at the bottom into the debt destinations, and deletes this file in the same commit.

## Context

Every run card prints its length as raw seconds (`3900s`). Operators convert in their heads, and a
long run is hard to tell from a short one at a glance.

## Intent (the one thing that must be true when this is done)

An operator glancing at a run card reads its length as hours and minutes, like `1h 05m`.

## Your calls (settled with the operator — do not reopen)

- **Format for a run over an hour** → "like `1h 05m`, minutes always two digits"
- **Rounding** → "round down, nobody cares about seconds once it's over a minute"

## Agent's calls (resolve during execution, never escalate)

- Where the tests live — follow `CLAUDE.md`.

## Canon sections (read these, and only these, before the first slice)

- `docs/time.md §1` — the display rule this changes.

## Where it runs

**A worktree, always** — `wt/duration-format`, created by `/dispatch`, squashed onto the trunk by `/land`.

## Model policy

Implementation: `opus` / `medium`. Escalate a slice to `opus` / `high` after 2 failed gate cycles.

## Handoff (answered by the operator as the last question of `/intent`)

Auto: **both**

## Slices

### S1 — run cards show `1h 05m`

- Files: `src/duration.ts`, `src/duration.test.ts`, `src/run-card.ts`
- Do: replace `formatSeconds` with `formatDuration(seconds)` rendering hours and minutes per the
  calls above; `runCardLine` uses it.
- `[verify]`: `.claude/scripts/deliver/gate.sh --slice S1`

## Gates (every slice, non-negotiable)

`.claude/scripts/deliver/gate.sh --slice <id>` per slice, `--full` once at the end.

## Out of scope

- `[boundary]` Localised unit names — English `h`/`m` only in this version.
- `[gap]` Durations in the CSV export still print seconds.

## Decisions (agent-made)

<!-- /deliver appends here. One entry per fork it resolved alone. -->

## Not delivered

Tag every entry `[agent]` or `[operator]`.

<!-- /deliver appends here at the end. -->
EOF

git add -A && git commit -qm "demo: baseline with the duration-format plan"

if [ "$mode" = worktree ]; then
  rmdir "$ws" 2>/dev/null || true
  git worktree add -q -b wt/duration-format "$ws"
fi

# `delivered`: main checkout in the workspace, plus the finished run's worktree beside it at
# ../demo-wt-duration-format with its commits and the Decisions entry /deliver wrote.
if [ "$mode" = delivered ]; then
  wt="$(dirname "$ws")/demo-wt-duration-format"
  git worktree add -q -b wt/duration-format "$wt"
  cd "$wt"
  cat > src/duration.ts <<'EOF'
// Display formatting for durations. Canon: docs/time.md §1.
export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h === 0) return `${m}m`;
  return `${h}h ${String(m).padStart(2, "0")}m`;
}
EOF
  sed -i.bak 's/formatSeconds/formatDuration/g' src/run-card.ts && rm src/run-card.ts.bak
  git commit -qam "feat(display): run cards show hours and minutes"
  printf 'import { expect, test } from "vitest";\nimport { formatDuration } from "./duration.js";\n\ntest("1h 05m", () => expect(formatDuration(3900)).toBe("1h 05m"));\n' > src/duration.test.ts
  git add -A && git commit -qm "test(display): formatDuration"
  awk '{ print } /^<!-- \/deliver appends here. One entry per fork/ { print "- **Under an hour renders minutes only (`45m`)** — why: an operator reads `45m` faster than `0h 45m`. Reverse by: drop the `h === 0` branch in `src/duration.ts`." }' \
    docs/plans/duration-format.md > plan.tmp && mv plan.tmp docs/plans/duration-format.md
  git commit -qam "docs(plan): record agent decisions"
fi
