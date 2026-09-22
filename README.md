# workflow — Claude Code plugin

The two-phase workflow skills, served to every Claude profile on this machine from this checkout:

| Skill | Job |
|---|---|
| `/intent` | interview the operator, write the plan contract |
| `/dispatch` | create the worktree, launch the unattended `/deliver` run, watch it |
| `/deliver` | execute a plan to completion with zero interaction |
| `/land` | squash-merge a finished worktree branch onto the trunk |
| `/debt-review` | drain the carried-debt pool into the next `/intent` wave |
| `/transcribe` | local audio/video → text (mlx-whisper; needs `ffmpeg` and `uv`) |

Project-specific facts never live here — each repo carries its own `.claude/workflow.md` and
`.claude/scripts/`.

## How it is installed

This repo is both the marketplace (`claude-plugin-intent`) and the plugin (`workflow`). Each profile
has it added as a local directory marketplace:

```sh
for p in ~/.claude ~/.claude-work ~/.claude-personal; do
  CLAUDE_CONFIG_DIR=$p claude plugin marketplace add ~/Projects/claude-plugin-intent
  CLAUDE_CONFIG_DIR=$p claude plugin install workflow@claude-plugin-intent
done
```

A directory marketplace loads the plugin **in place**: `${CLAUDE_PLUGIN_ROOT}` expands to this
checkout, and an edit here is live in every profile's next skill load — no sync, no update command.
The flip side: **whatever is checked out here is production** for all four repos. Experiment in a
separate worktree, not by switching this checkout's branch.

This replaced `~/.claude-skills/sync.sh`, which `cp -R`'d the tree into each profile. That script now
hard-fails; do not recreate `skills/{intent,dispatch,deliver,land,debt-review,transcribe}` in any
profile — a profile copy shadows nothing and drifts silently.

## `CLAUDE_CONFIG_DIR` vs `${CLAUDE_PLUGIN_ROOT}`

- **Where the scripts live** → `${CLAUDE_PLUGIN_ROOT}/skills/...`, substituted by Claude Code when a
  skill loads.
- **Which profile a wave belongs to** → still `CLAUDE_CONFIG_DIR`. `launch-run.sh` refuses to run
  without it and pins it into the tmux child; `launch-run.sh`, `watch-runs.sh` and `cockpit-addr.sh`
  keep runtime state under `$CLAUDE_CONFIG_DIR/dispatch-runs/`. The watcher's state file is keyed
  `<repo>-<cockpit key>` because one profile drives two repos.

## Evals

`evals/` holds `claude plugin eval` cases for the pipeline's measured failures. Run the suite
before committing a skill change, since this checkout is live for every profile:

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

Every case is a **dry run**: Bash, Write and Edit are withheld, so no worktree, tmux session or push
ever happens. The prompt supplies each script's output, and the model writes the commands and files it
would produce into its reply, which the graders read. `--scaffold` builds a small synthetic project
(`evals/_fixture/make-project.sh`) as each run's workspace, because every skill starts by reading
the project's `.claude/workflow.md`; the flag only runs the scaffold scripts in this repo. Each case runs 3× with the plugin and
3× without; `Δ` is what the skills add. Use `--runs 1 --ablation none --case <name>` while iterating.
Results go to `evals/results/` (gitignored).

## Not here

- `context-search` — owned by the `jbcontext` installer (`jbcontext upgrade` rewrites
  `~/.claude/skills/context-search`, and `~/.claude-skills/sync-jbcontext.sh` links it into the other
  profiles). A copy here would be a second source for it.
- Repo-specific skills and scripts (e.g. loadnex's `deploy`, `operate`, `decompose`,
  `.claude/scripts/**`) stay in their repos.
