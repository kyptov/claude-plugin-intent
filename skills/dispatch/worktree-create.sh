#!/bin/bash
# WorktreeCreate hook — builds the worktree every `isolation: "worktree"` agent runs in, so a
# dispatched /deliver run starts in a tree that is ready to gate: branch, dependency install, and the
# project's own per-worktree setup (synced env files, a database of its own, …).
#
#   stdin:  {"name": "<suggested slug>", "cwd": "<session cwd>", …}   (Claude Code hook input)
#   stdout: the absolute path of the created worktree — and nothing else
#
# In a project with a `.claude/workflow.md` declaration:
#   worktree  ../<proj>-wt-<name>, on <prefix>/<name> from the trunk (origin/HEAD, else main).
#             /deliver renames the branch to <prefix>/<slug> as its first act — the hook is handed an
#             agent id, never the plan, so the plan's slug cannot be known here.
#   setup     `.claude/scripts/dispatch/worktree-setup.sh <worktree>`, run from the main checkout,
#             when the project has one. Otherwise the install is inferred from the lockfile
#             (pnpm/yarn/npm/bun) and a `worktree:sync` package script is run if the repo declares one.
#   setup output must be gitignored: anything it leaves untracked reads as a dirty worktree to land.sh.
#   failure   a setup that fails tears down what it built (the project's worktree-teardown.sh, then
#             the worktree and branch) and exits non-zero, so the agent never starts in a half-built
#             tree and nothing is left behind that no session knows about.
# Anywhere else: a plain worktree at .claude/worktrees/<name> on worktree-<name>, no setup — the same
# shape Claude Code makes without a hook, so the plugin changes nothing in projects that do not use it.
#
# env: WT_BRANCH_PREFIX (default wt) — the branch namespace, same knob as land.sh.
# Exit: 0 created · 64 bad input · 65 not a git repo · 67 worktree or branch exists · 68 git failed
#       · 69 setup failed (and was torn down)
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile.
set -uo pipefail

# Stdout carries the path and nothing else: everything a step prints goes to stderr, which Claude Code
# shows when the hook fails.
exec 3>&1 1>&2

in=$(cat)
name=$(printf '%s' "$in" | jq -r '.name // empty' 2>/dev/null)
cwd=$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$name" ] || { echo "WorktreeCreate: no name on stdin"; exit 64; }
case "$name" in
  (.*|*[!A-Za-z0-9._-]*) echo "WorktreeCreate: refusing worktree name '$name'"; exit 64 ;;
esac
[ -n "$cwd" ] || cwd=$PWD

# Main checkout from the COMMON git dir, so a session sitting in a worktree gets the same answer.
common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "WorktreeCreate: $cwd is not in a git repository"; exit 65; }
repo=$(cd "$(dirname "$common")" && pwd -P)
proj=$(basename "$repo")

if [ ! -f "$repo/.claude/workflow.md" ]; then
  wt="$repo/.claude/worktrees/$name"
  branch="worktree-$name"
  [ ! -e "$wt" ] || { echo "WorktreeCreate: $wt already exists"; exit 67; }
  # Keep the in-repo worktree directory out of the main checkout's status.
  grep -qsxF '.claude/worktrees/' "$common/info/exclude" \
    || { mkdir -p "$common/info" && echo '.claude/worktrees/' >> "$common/info/exclude"; }
  git -C "$repo" worktree add -q "$wt" -b "$branch" "$(git -C "$cwd" rev-parse HEAD)" || exit 68
  echo "$wt" >&3
  exit 0
fi

prefix=${WT_BRANCH_PREFIX:-wt}
trunk=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=main
wt="$(dirname "$repo")/$proj-wt-$name"
branch="$prefix/$name"
if [ -e "$wt" ] || git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "WorktreeCreate: $wt or $branch already exists"; exit 67
fi

echo "==> worktree $wt on $branch from $trunk"
git -C "$repo" worktree add -q "$wt" -b "$branch" "$trunk" || exit 68

setup="$repo/.claude/scripts/dispatch/worktree-setup.sh"
teardown="$repo/.claude/scripts/dispatch/worktree-teardown.sh"

undo() {
  echo "WorktreeCreate: $1 — removing the half-built worktree"
  [ -x "$teardown" ] && (cd "$wt" && "$teardown" "$wt") || true
  git -C "$repo" worktree remove --force "$wt" || true
  git -C "$repo" branch -D "$branch" || true
  exit 69
}

if [ -x "$setup" ]; then
  echo "==> setup: $setup $wt"
  (cd "$repo" && "$setup" "$wt") || undo "worktree-setup.sh failed"
else
  install_cmd=""
  if [ -f "$repo/pnpm-lock.yaml" ]; then install_cmd="pnpm install"
  elif [ -f "$repo/yarn.lock" ]; then install_cmd="yarn install --frozen-lockfile"
  elif [ -f "$repo/bun.lockb" ] || [ -f "$repo/bun.lock" ]; then install_cmd="bun install"
  elif [ -f "$repo/package-lock.json" ]; then install_cmd="npm ci"
  fi
  if [ -n "$install_cmd" ]; then
    echo "==> install: $install_cmd"
    (cd "$wt" && eval "$install_cmd") || undo "install failed"
  fi
  # The project's own worktree sync (copies gitignored local config/env per its allow-list), run
  # from the MAIN checkout, which is where those files live.
  if [ -f "$repo/package.json" ] && jq -e '.scripts["worktree:sync"]' "$repo/package.json" >/dev/null 2>&1; then
    case "$install_cmd" in
      (yarn*) sync_cmd="yarn worktree:sync" ;;
      (bun*) sync_cmd="bun run worktree:sync" ;;
      (npm*) sync_cmd="npm run worktree:sync --" ;;
      (*) sync_cmd="pnpm worktree:sync" ;;
    esac
    echo "==> sync: $sync_cmd $wt"
    (cd "$repo" && eval "$sync_cmd \"$wt\"") || undo "worktree sync failed"
  fi
fi

echo "$wt" >&3
exit 0
