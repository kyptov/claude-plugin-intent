# workflow — Claude Code plugin

A two-phase workflow for Claude Code: you are interviewed once, up front, and everything after that
runs unattended in its own git worktree until the feature lands on the trunk as a single commit.

| Skill | Job |
|---|---|
| `/intent` | interview the operator, write the plan contract; `--quick` skips the interview for a small visible tweak |
| `/dispatch` | create the worktree, launch the unattended `/deliver` run, watch it |
| `/deliver` | execute a plan to completion with zero interaction, logging every decision it makes alone |
| `/land` | squash-merge a finished worktree branch onto the trunk |
| `/debt-review` | drain the carried-debt pool into the next `/intent` wave |
| `/transcribe` | local audio/video → text (mlx-whisper; needs `ffmpeg` and `uv`) |

## How a feature moves

1. **`/intent`**, in your main checkout: a few rounds of plain-language questions about *what* the
   feature does. The agent decides *how* on its own, writes a plan contract (intent, your answers,
   slices with verify commands, what is out of scope), briefs you in a few paragraphs, and asks one
   question: build it, or just save the plan. The plan is committed on the trunk.
2. **`/dispatch`** creates a worktree on `wt/<slug>`, starts a Claude Code Remote Control session in
   a per-project `tmux` socket, and hands it `/deliver <plan>`. The session that dispatched (the
   *cockpit*) arms a watcher and waits.
3. **`/deliver`** runs in the worktree with no questions allowed: forks are decided against the plan's
   intent and logged in the plan, each slice is gated and committed, and the run reports
   `DELIVERED <slug> — gates: green | RED` back to the cockpit.
4. **`/land`**, on a green verdict: files the plan's leftovers into the project's debt files, squashes
   the branch into one commit, rebases, re-runs the gates, fast-forwards the trunk, pushes, and removes
   the worktree and branch.

`/debt-review` runs on a cadence (weekly) and turns the debt pool back into ready-to-paste `/intent`
commands.

## Requirements

- macOS. The scripts target `/bin/bash` 3.2 and use BSD `stat`, `lsof` and `ps`.
- `git`, `tmux`, `jq`, `python3`, and the Claude Code CLI.
- For `/transcribe`: Apple Silicon, `ffmpeg`, and `uv`.

## Install

```sh
claude plugin marketplace add kyptov/claude-plugin-intent
claude plugin install workflow@claude-plugin-intent
```

**`CLAUDE_CONFIG_DIR` must be set in the session you dispatch from.** `launch-run.sh` refuses to run
without it, pins it into the run's `tmux` command, and keeps runtime state (dispatch records, watcher
state) under `$CLAUDE_CONFIG_DIR/dispatch-runs/`. With the default profile:

```sh
export CLAUDE_CONFIG_DIR="$HOME/.claude"    # in your shell profile
```

To work on the plugin itself, add a clone as a local directory marketplace instead. It is loaded **in
place**: `${CLAUDE_PLUGIN_ROOT}` expands to your clone, and an edit is live at the next skill load.
That also means whatever is checked out there is what every project runs, so experiment in a separate
worktree rather than by switching the clone's branch.

```sh
claude plugin marketplace add ~/path/to/claude-plugin-intent
claude plugin install workflow@claude-plugin-intent
```

## Bootstrap a project

The plugin carries no project facts. Every skill starts by reading **`.claude/workflow.md`** in the
project root, and the deterministic steps — preflight, gates, run report, plan check — are scripts the
project owns under `.claude/scripts/`, because only the project knows its gates. A project is ready
after four steps.

### 1. Write the declaration, `.claude/workflow.md`

It names, in whatever headings suit you:

- **Trunk and remote** — the trunk branch and its remote.
- **Gates** — the full gate command line, any conditional gates (which paths trigger which extra
  gate), and their traps.
- **Scripted mechanics** — a table of the scripts from step 3 with their exit codes (the bootstrap
  prompts add these rows).
- **Plans** — where plans live and which template they follow.
- **Binding rules** — the project's rules file (e.g. `CLAUDE.md`), which wins over the declaration.
- **Users** — who uses the product, so `/intent` can ask in their terms.
- **Worktree setup** — the install command (`--install`) and any step that copies gitignored local
  config into a new worktree (`--sync`).
- **Branch namespace** (default `wt`) and **session tag**, a short project abbreviation used to pair a
  cockpit with its runs (`launch-run.sh --tag`).
- **Deploy commands** — listed so `/deliver` and `/land` know never to run them.
- **Protected files** — secret/env files a run must stop before touching.
- **Model policy** — implementation model and effort, the escalation after repeated red gates, and the
  review effort for sensitive areas.
- **Canon docs** — the documents plans cite as `doc §n`, including the roadmap `/debt-review` ranks
  against.
- **Debt destinations** — the debt pool, the operator queue (work only a human can do), the branch
  triage file (branches that could not land), and any plan files that are kept rather than deleted.
  Optionally a debt **intake** directory: `/land` then writes each plan's leftovers to
  `<dir>/<slug>.md` instead of editing the pool, and `/debt-review` folds them in — worth declaring
  once parallel landings start conflicting on the pool file.
- **Read-only production check** — the diagnostic `/debt-review` may use to confirm operator work is
  done.

`evals/_fixture/make-project.sh` writes a complete minimal declaration for a demo project; start from
that.

### 2. Add the plan template

Put it where the declaration says. `/intent` fills it, `/deliver` appends to it, `/land` routes on it,
so it needs these sections: `Context`, `Intent`, `Your calls`, `Agent's calls`, `Canon sections`,
`Where it runs`, `Model policy`, `Handoff` (with an `Auto: **<nothing | dispatch | deliver | both>**`
line), `Slices` (each with `- Files:` and a `[verify]` command), `Gates`, `Out of scope` (items marked
`[boundary]` or `[gap]`), `Decisions (agent-made)`, and `Not delivered` (entries tagged `[agent]` or
`[operator]`). The same fixture has a complete template.

Create the debt files the declaration names, even if empty.

### 3. Build the mechanics scripts

Each `BOOTSTRAP.md` holds a self-contained prompt. Paste its fenced block into a Claude session in the
project. The prompt states the contract (the exit codes the skill routes on), builds the script
against your declaration, adds its row to the declaration's Scripted mechanics table, and proves it
works on throwaway fixtures before it finishes.

| Prompt | Builds | Without it |
|---|---|---|
| `skills/deliver/BOOTSTRAP.md` | `.claude/scripts/deliver/{preflight,gate,report}.sh` and a shared `lib.sh` | `/deliver` stops before the first edit |
| `skills/dispatch/BOOTSTRAP.md` | `.claude/scripts/dispatch/preflight.sh` — land lock, dirty checkout, `## Handoff`, file overlap with unlanded branches | `/dispatch` stops |
| `skills/intent/BOOTSTRAP.md` | `.claude/scripts/intent/plan-check.sh` — the one machine check on a plan before it is approved | `/intent` checks the plan by hand and says the script is missing |

The three are independent; paste them in any order, or all in one session.

### 4. Try it

Run `/intent --quick <a one-line visible tweak>` in the main checkout. It should write and commit a
plan, dispatch it, and land it when the run reports green.

## Evals

`evals/` holds `claude plugin eval` cases for the pipeline's known failure modes. Run the suite before
committing a skill change:

```sh
claude plugin eval . --scaffold --trust-plugin --no-publish -j 4 --threshold 0.8
```

| Case | Guards against |
|---|---|
| `dispatch-arms-watcher` | a wave launched with no `watch-runs.sh --watch` armed in the same turn, or armed without the dispatching profile |
| `intent-plan-passes-check` | a plan `plan-check.sh` would reject: missing section, template placeholder, slice without `- Files:`/`[verify]`, unmarked out-of-scope item; a plan left uncommitted |
| `intent-quick-lane` | `/intent --quick` on a one-line tweak that still interviews, asks for approval, skips the plan commit (or sweeps other files into it), or stops short of `/dispatch` |
| `deliver-decides-alone` | `/deliver` asking the operator at a fork instead of deciding and logging it |
| `land-on-green-verdict` | `Handoff: both` plus a green `DELIVERED`, and nobody invokes `/land` |
| `land-holds-on-red` | the guard for the case above: a `gates: RED` verdict must not land |
| `land-files-debt-to-intake` | a `/land` that writes a plan's debt leftovers into the pool file when the declaration names an intake directory — the edit two parallel landings conflict on |

Every case is a **dry run**: Bash, Write and Edit are withheld, so no worktree, tmux session or push
ever happens. The prompt supplies each script's output, and the model writes the commands and files it
would produce into its reply, which the graders read. `--scaffold` builds the demo project
(`evals/_fixture/make-project.sh`) as each run's workspace. Each case runs 3× with the plugin and 3×
without; `Δ` is what the skills add. Use `--runs 1 --ablation none --case <name>` while iterating.
Results go to `evals/results/` (gitignored).
