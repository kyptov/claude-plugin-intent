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

## Not here

- `context-search` — owned by the `jbcontext` installer (`jbcontext upgrade` rewrites
  `~/.claude/skills/context-search`, and `~/.claude-skills/sync-jbcontext.sh` links it into the other
  profiles). A copy here would be a second source for it.
- Repo-specific skills and scripts (e.g. loadnex's `deploy`, `operate`, `decompose`,
  `.claude/scripts/**`) stay in their repos.
