#!/bin/bash
# Land a finished worktree branch onto the trunk as exactly one commit — the deterministic half of
# /land. The judgment half (sweeping the plan's leftovers into the debt files, writing the squash
# message, resolving a conflict) stays with the model and happens BEFORE this runs.
#
#   land.sh <worktree-path> --message-file <file> --gates "<the declaration's full gate line>"
#           [--extra-gate "<cmd>"]... [--teardown "<cmd run inside the worktree before removal>"]
#           [--trunk <branch>] [--attempts 3]
#   env: WT_BRANCH_PREFIX (default wt) — the branch namespace, same knob as watch-runs.sh
#
# Project-agnostic: gates and teardown come from the project's .claude/workflow.md via flags.
#
# Sequence: land lock → squash (reset --soft to merge-base + one commit) → up to N × (fetch, rebase
# onto the trunk TIP, gates, fast-forward the main checkout) → push → kill the run's tmux session →
# per-worktree teardown → remove worktree + branch → release lock. Exit codes name the failure so the
# skill can route it:
#   0 landed   20 rebase conflict (branch + worktree left as they are)   21 gates red after rebase
#   22 push refused   23 fast-forward refused 3× (trunk kept moving)   24 empty squash (nothing to land)
#   25 local <trunk> and origin/<trunk> diverged — needs a human, retrying cannot fix it
#   10 lock held by another landing   1x argument / repo errors
#
# "the trunk TIP" is deliberate and is NOT always origin/<trunk>: when a peer landed into the shared
# main checkout without pushing, local <trunk> is ahead of origin and the rebase must target local,
# or the --ff-only step is impossible by construction. See the comment in the loop.
#
# NOTE for a project whose gates need a wrapper to reach its database (e.g. loadnex's `lan`, which
# starts a loopback relay macOS otherwise blocks `node` from): invoke THIS SCRIPT under that wrapper.
# The gates and the teardown are children of this process, so wrapping the script wraps both; passing
# a wrapped --gates string leaves the teardown unwrapped and leaks the worktree database.
# The lock is released on EVERY exit path except 10 (it is not ours to release).
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile.
set -uo pipefail

wt=""; msgfile=""; gates=""; extra=""; teardown=""; trunk=""; attempts=3
prefix=${WT_BRANCH_PREFIX:-wt}
while [ $# -gt 0 ]; do
  case "$1" in
    --message-file) msgfile=$2; shift 2 ;;
    --gates) gates=$2; shift 2 ;;
    --extra-gate) extra="$extra && $2"; shift 2 ;;
    --teardown) teardown=$2; shift 2 ;;
    --trunk) trunk=$2; shift 2 ;;
    --attempts) attempts=$2; shift 2 ;;
    -*) echo "unknown flag $1" >&2; exit 64 ;;
    *) wt=$1; shift ;;
  esac
done
[ -n "$wt" ] && [ -d "$wt" ] || { echo "usage: land.sh <worktree-path> --message-file <file> [flags]" >&2; exit 64; }
[ -n "$msgfile" ] && [ -s "$msgfile" ] || { echo "--message-file is required and must be non-empty" >&2; exit 64; }
[ -n "$gates" ] || { echo "--gates is required: pass the project declaration's full gate line" >&2; exit 64; }
wt=$(cd "$wt" && pwd)

common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a worktree" >&2; exit 65; }
repo=$(dirname "$common")
[ "$repo" != "$wt" ] || { echo "$wt is the main checkout, not a worktree" >&2; exit 65; }
proj=$(basename "$repo")
[ -n "$trunk" ] || trunk=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=main
branch=$(git -C "$wt" symbolic-ref --short HEAD) || { echo "worktree is not on a branch" >&2; exit 65; }
slug=${branch#"$prefix"/}

lock="$repo/.claude/land.lock"
mkdir -p "$repo/.claude"
if [ -e "$lock" ]; then echo "another run is landing: $(cat "$lock")" >&2; exit 10; fi
echo "$branch $(date -u +%FT%TZ)" > "$lock"
release() { rm -f "$lock"; }
trap release EXIT

dirty=$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')
[ "$dirty" = 0 ] || { echo "worktree has $dirty uncommitted paths — commit the sweep first" >&2; exit 66; }

echo "==> squash $branch onto one commit"
base=$(git -C "$wt" merge-base "$trunk" HEAD) || exit 65
if git -C "$wt" diff --quiet "$base" HEAD -- .; then echo "empty squash — the run delivered nothing" >&2; exit 24; fi
git -C "$wt" reset --soft "$base" && git -C "$wt" commit -q -F "$msgfile" || exit 65

i=0
while [ "$i" -lt "$attempts" ]; do
  i=$((i + 1))
  echo "==> attempt $i/$attempts: fetch, then pick the trunk tip to rebase onto"
  git -C "$repo" fetch -q origin || exit 65

  # The rebase target and the fast-forward target MUST be the same commit. They are not,
  # whenever a peer landed into the shared main checkout without pushing: `origin/<trunk>`
  # is then BEHIND local `<trunk>`, rebasing onto origin drops the commits local has, and
  # the `--ff-only` below can never succeed — every attempt then fails identically while
  # reporting "trunk moved", which is the opposite of what happened (measured: 3/3 attempts
  # burned on a trunk that was not moving at all).
  ab=$(git -C "$repo" rev-list --left-right --count "$trunk...origin/$trunk") || exit 65
  local_ahead=$(printf '%s' "$ab" | cut -f1)
  origin_ahead=$(printf '%s' "$ab" | cut -f2)
  if [ "${local_ahead:-0}" -gt 0 ] && [ "${origin_ahead:-0}" -gt 0 ]; then
    echo "$trunk and origin/$trunk have DIVERGED — $local_ahead local, $origin_ahead remote, neither contains the other." >&2
    echo "No retry can win this: reconcile the two by hand, then re-run. Branch and worktree left untouched." >&2
    exit 25
  fi
  if [ "${local_ahead:-0}" -gt 0 ]; then
    target=$trunk
    echo "WARN: origin/$trunk is $local_ahead commit(s) behind local $trunk — a peer landed without pushing." >&2
    echo "WARN: rebasing onto local $trunk instead; the push below WILL carry those $local_ahead peer commit(s) to origin." >&2
  else
    target="origin/$trunk"
  fi

  echo "==> rebase onto $target"
  if ! git -C "$wt" rebase -q "$target"; then
    git -C "$wt" rebase --abort 2>/dev/null
    echo "rebase conflict — branch and worktree left untouched" >&2
    exit 20
  fi
  echo "==> gates: $gates$extra"
  if ! (cd "$wt" && eval "$gates$extra"); then echo "gates red after rebase" >&2; exit 21; fi
  echo "==> fast-forward $trunk in the main checkout"
  git -C "$repo" checkout -q "$trunk" 2>/dev/null
  if git -C "$repo" merge -q --ff-only "$branch"; then break; fi
  echo "fast-forward refused — $trunk moved during the gates; retrying" >&2
  [ "$i" -lt "$attempts" ] || exit 23
done

echo "==> push"
git -C "$repo" push -q origin "$trunk" || exit 22
hash=$(git -C "$repo" rev-parse --short HEAD)
subject=$(git -C "$repo" log -1 --format=%s)

echo "==> kill the run's session, then tear down, then remove — in that order"
tmux -L "impl-$proj" kill-session -t "impl-$proj-$slug" 2>/dev/null || true
if [ -n "$teardown" ]; then
  (cd "$wt" && eval "$teardown") || echo "WARN: per-worktree teardown failed — continuing the landing (gc will sweep)" >&2
fi
git -C "$repo" worktree remove --force "$wt" || echo "WARN: worktree remove failed: $wt" >&2
git -C "$repo" branch -d "$branch" || echo "WARN: branch -d refused for $branch (not merged?)" >&2

echo "LANDED $hash $subject"
exit 0
