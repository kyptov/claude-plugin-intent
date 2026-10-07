#!/bin/bash
# Remove a worktree that holds no work — the WorktreeRemove hook, and the cockpit's cleanup for a run
# that ended with nothing on its branch. Claude Code keeps a hook-built agent worktree when the agent
# ends (its result carries the worktreePath), so the cockpit runs this itself for an empty run:
#
#   echo '{"worktree_path":"<path>"}' | worktree-remove.sh
#
# A worktree that holds work is /land's to remove, never this script's.
#
#   stdin: {"worktree_path": "<absolute path>", …}   (Claude Code hook input)
#
# Order matters and matches land.sh: the project's per-worktree teardown first (it derives its target
# — a database, a port — from the worktree's own path), then the worktree, then its branch with
# `branch -d`, which refuses a branch holding unmerged commits.
#
# Exit: 0 removed or already gone · 64 bad input · 65 refused (the main checkout, or not a worktree)
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile.
set -uo pipefail

wt=$(jq -r '.worktree_path // empty' 2>/dev/null)
[ -n "$wt" ] || { echo "WorktreeRemove: no worktree_path on stdin" >&2; exit 64; }
[ -d "$wt" ] || exit 0

common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "WorktreeRemove: $wt is not in a git repository" >&2; exit 65; }
repo=$(cd "$(dirname "$common")" && pwd -P)
[ "$repo" != "$(cd "$wt" && pwd -P)" ] || { echo "WorktreeRemove: refusing to remove the main checkout" >&2; exit 65; }
branch=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null)

teardown="$repo/.claude/scripts/dispatch/worktree-teardown.sh"
if [ -x "$teardown" ]; then
  (cd "$wt" && "$teardown" "$wt") >&2 || echo "WARN: worktree-teardown.sh failed for $wt" >&2
fi
git -C "$repo" worktree remove --force "$wt" >&2 || { echo "WorktreeRemove: git worktree remove failed: $wt" >&2; exit 1; }
[ -z "$branch" ] || git -C "$repo" branch -d "$branch" >&2 || echo "WARN: kept $branch (it holds unmerged commits)" >&2
exit 0
