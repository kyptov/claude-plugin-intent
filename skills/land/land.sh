#!/bin/bash
# Land a finished worktree branch onto the trunk as exactly one commit — the deterministic half of
# /land. The judgment half (sweeping the plan's leftovers into the debt files, writing the squash
# message, resolving a conflict) stays with the model and happens BEFORE this runs.
#
#   land.sh <worktree-path> --message-file <file> --gates "<the declaration's full gate line>"
#           [--extra-gate "<cmd>"]... [--teardown "<cmd run inside the worktree before removal>"]
#           [--trunk <branch>] [--attempts 3] [--lock-wait <minutes>]
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
#   10 a LIVE landing still held the lock after --lock-wait minutes   1x argument / repo errors
#
# THE LOCK WAITS INSTEAD OF BOUNCING (measured on loadnex: 36 of 111 /land invocations were blocked,
# and 15 cockpits needed 3+ calls to land one branch). Two landings that overlap are the normal case
# in a wave, not an error — the second one belongs in a queue, not back in the model's lap, because
# every bounce costs a cockpit turn and the operator's attention. So:
#   - the lock is a DIRECTORY, taken with `mkdir` (atomic; macOS has no flock(1)). The old
#     "test -e then write" was a race two simultaneous landings could both win.
#   - it records pid + that process's start time + branch + the cockpit that owns it. Liveness is
#     `kill -0 <pid>` AND the same start time, because a PID alone is reused.
#   - a holder that is alive → poll until it releases, up to --lock-wait minutes (default 25: above
#     a healthy worst case of attempts × gates, below "wedged"; a project whose suite is slow says
#     so in its declaration — ml-billing's 8-16 minute suite needs 50).
#   - a holder that is GONE → take the lock over at once, whatever its age. Only SIGKILL (a crash, a
#     hard-killed tool call) can leave one behind: the EXIT trap releases on TERM, INT and HUP.
#   - a legacy FILE lock (previous versions wrote one) carries no pid, so it falls back to the
#     branch: the branch still exists → a landing may be in flight, wait; the branch is gone → that
#     landing finished, the file is junk, remove it.
# Branch existence is NOT used when a pid is available: /land leaves the branch in place on every
# failure exit (20, 21, 22, 25), so "branch exists" stays true for hours after the lock is released.
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

wt=""; msgfile=""; gates=""; extra=""; teardown=""; trunk=""; attempts=3; lock_wait=25
prefix=${WT_BRANCH_PREFIX:-wt}
while [ $# -gt 0 ]; do
  case "$1" in
    --message-file) msgfile=$2; shift 2 ;;
    --gates) gates=$2; shift 2 ;;
    --extra-gate) extra="$extra && $2"; shift 2 ;;
    --teardown) teardown=$2; shift 2 ;;
    --trunk) trunk=$2; shift 2 ;;
    --attempts) attempts=$2; shift 2 ;;
    --lock-wait) lock_wait=$2; shift 2 ;;
    -*) echo "unknown flag $1" >&2; exit 64 ;;
    *) wt=$1; shift ;;
  esac
done
[ -n "$wt" ] && [ -d "$wt" ] || { echo "usage: land.sh <worktree-path> --message-file <file> [flags]" >&2; exit 64; }
[ -n "$msgfile" ] && [ -s "$msgfile" ] || { echo "--message-file is required and must be non-empty" >&2; exit 64; }
# Absolute, because the commit below runs with the WORKTREE as its cwd: a relative path that
# resolved fine for the caller was read relative to the worktree and failed there — after the
# `reset --soft` had already run, leaving the branch squashed but uncommitted.
case "$msgfile" in /*) ;; *) msgfile="$PWD/$msgfile" ;; esac
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
held_lock=0
release() { [ "$held_lock" = 1 ] && rm -rf "$lock"; }
trap release EXIT

# The cockpit this landing belongs to, for the waiter's message only — never for liveness. Walk up
# to the `claude` ancestor and read the name Claude Code records for that pid, the same registry
# cockpit-addr.sh resolves against. Best-effort: an unnamed or unresolvable session is not an error.
owner_session() {
  p=$$ ; n=0
  while [ "$n" -lt 8 ] && [ "${p:-1}" -gt 1 ]; do
    f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$p.json"
    if [ -f "$f" ]; then jq -r '.name // empty' "$f" 2>/dev/null; return; fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') ; n=$((n + 1))
  done
}
# A pid is reused; a pid whose process started at the recorded moment is not.
pid_started() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$(pid_started "$1")" = "$2" ]; }

lock_started=$(date +%s); last_report=""; ownerless_since=""
while :; do
  if mkdir "$lock" 2>/dev/null; then
    { echo "pid=$$"; echo "started=$(pid_started $$)"; echo "branch=$branch"
      echo "session=$(owner_session)"; echo "since=$(date -u +%FT%TZ)"; } > "$lock/owner"
    held_lock=1
    break
  fi

  if [ -f "$lock" ]; then
    # Legacy file lock: no pid to ask about, so fall back to the branch it names.
    l_branch=$(cut -d' ' -f1 < "$lock" 2>/dev/null)
    if [ -n "$l_branch" ] && ! git -C "$repo" show-ref -q --verify "refs/heads/$l_branch"; then
      echo "WARN: legacy lock for $l_branch whose branch is gone — that landing finished; removing it" >&2
      rm -f "$lock"; continue
    fi
    l_pid=""; l_start=""; l_session=""; l_since=""
  else
    l_pid=$(sed -n 's/^pid=//p' "$lock/owner" 2>/dev/null)
    l_start=$(sed -n 's/^started=//p' "$lock/owner" 2>/dev/null)
    l_branch=$(sed -n 's/^branch=//p' "$lock/owner" 2>/dev/null)
    l_session=$(sed -n 's/^session=//p' "$lock/owner" 2>/dev/null)
    l_since=$(sed -n 's/^since=//p' "$lock/owner" 2>/dev/null)
    if [ -n "$l_pid" ] && ! alive "$l_pid" "$l_start"; then
      echo "WARN: stale lock from ${l_branch:-?} (pid $l_pid is gone or was recycled, held since ${l_since:-?}) — taking it over" >&2
      rm -rf "$lock"; continue
    fi
    if [ -z "$l_pid" ]; then
      # Either a lock dir caught between its mkdir and its owner file (milliseconds), or one whose
      # owner never got written because that process died in between. Give it a moment, then treat
      # it as junk — an ownerless lock can never be released by anyone.
      [ -n "$ownerless_since" ] || ownerless_since=$(date +%s)
      if [ $(( $(date +%s) - ownerless_since )) -ge 15 ]; then
        echo "WARN: lock with no owner record for 15s — removing it" >&2
        rm -rf "$lock"; ownerless_since=""
      fi
      sleep 2; continue
    fi
    ownerless_since=""
  fi

  waited=$(( ($(date +%s) - lock_started) / 60 ))
  if [ "$waited" -ge "$lock_wait" ]; then
    echo "the lock on ${l_branch:-?}${l_session:+ ($l_session)} did not clear in ${waited}m" >&2
    if [ -n "$l_pid" ]; then
      echo "and its process (pid $l_pid) is still alive: that landing is stuck, not busy." >&2
    else
      echo "and it is a legacy lock naming a branch that still exists, so nothing here can judge" >&2
      echo "whether a landing still holds it. Check, then remove $lock by hand if it is dead." >&2
    fi
    echo "This branch is untouched — land it once the other one is resolved." >&2
    exit 10
  fi
  if [ "$waited" != "$last_report" ]; then   # once a minute, not once a tick
    echo "==> waiting for ${l_branch:-another landing}${l_session:+ ($l_session)} to release the lock — ${waited}m of ${lock_wait}m"
    last_report=$waited
  fi
  sleep 10
done

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
