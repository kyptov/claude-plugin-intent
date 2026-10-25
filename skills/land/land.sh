#!/bin/bash
# Land a finished worktree branch onto the trunk as exactly one commit — the deterministic half of
# /land. The judgment half (sweeping the plan's leftovers into the debt files, writing the squash
# message, resolving a conflict) stays with the model and happens BEFORE this runs.
#
#   land.sh <worktree-path> --message-file <file> --gates "<the declaration's full gate line>"
#           [--extra-gate "<cmd>"]... [--teardown "<cmd run inside the worktree before removal>"]
#           [--refresh "<cmd run inside the worktree after each rebase>"]
#           [--trunk <branch>] [--attempts 3] [--lock-wait <minutes>]
#
# Project-agnostic: gates and teardown come from the project's .claude/workflow.md via flags. Without
# --teardown, the project's `.claude/scripts/dispatch/worktree-teardown.sh <worktree>` runs when it
# exists — the same script the WorktreeRemove hook runs, so both ways a worktree ends tear down alike.
# Without --refresh, the project's `.claude/scripts/dispatch/worktree-refresh.sh <worktree>` runs after
# every successful rebase, before the gates, when it exists: the worktree was provisioned (database
# migrated, codegen run, deps installed) for the base it was dispatched from, and the rebase may have
# brought in migrations or a lockfile change that the gate line cannot know about.
#
# Sequence: land lock → squash (reset --soft to merge-base + one commit) → up to N × (fetch, rebase
# onto the trunk TIP, refresh, gates, fast-forward the main checkout) → push → per-worktree teardown →
# remove worktree + branch → release lock. Exit codes name the failure so the
# skill can route it:
#   0 landed   20 rebase conflict (branch + worktree left as they are)
#   21 refresh or gates red after rebase
#   22 push refused   23 fast-forward refused 3× (trunk kept moving)   24 empty squash (nothing to land)
#   25 local <trunk> and origin/<trunk> diverged — needs a human, retrying cannot fix it
#   26 uncommitted paths in the main checkout refused the fast-forward (branch rebased + green, kept)
#   10 a LIVE landing still held the lock after --lock-wait minutes   1x argument / repo errors
#
# THE LOCK WAITS INSTEAD OF BOUNCING. Two landings that overlap are the normal case in a wave, not
# an error — the second one belongs in a queue, not back in the model's lap, because every bounce
# costs a cockpit turn and the operator's attention. So:
#   - the lock is a DIRECTORY, taken with `mkdir` (atomic; macOS has no flock(1)).
#   - it records pid + that process's start time + branch + the cockpit that owns it (name and
#     session id). Liveness is
#     `kill -0 <pid>` AND the same start time, because a PID alone is reused.
#   - a holder that is alive → poll every 30s until it releases, up to --lock-wait minutes (default
#     $LAND_LOCK_WAIT_MINUTES, else 30: a healthy landing holds it 10–20 minutes; a project whose
#     suite is slow says so in its declaration — a 15-minute suite needs about 50). It prints the
#     holder once, then only on acquiring the lock or giving up: the wait is a queue, not progress.
#   - no wait-cycle check here: a landing holds the lock and waits on nothing, so a land-lock edge
#     never closes a cycle (skills/dispatch/wait-for.sh, the authority on cycles, says the same).
#   - a holder that is GONE → take the lock over at once, whatever its age. Only SIGKILL (a crash, a
#     hard-killed tool call) can leave one behind: the EXIT trap releases on TERM, INT and HUP.
#   - a lock with no owner record for 15s → junk (its process died between mkdir and writing the
#     owner); remove it.
# Branch existence is NOT a liveness signal: /land leaves the branch in place on every
# failure exit (20, 21, 22, 25), so "branch exists" stays true for hours after the lock is released.
#
# "the trunk TIP" is deliberate and is NOT always origin/<trunk>: when a peer landed into the shared
# main checkout without pushing, local <trunk> is ahead of origin and the rebase must target local,
# or the --ff-only step is impossible by construction. See the comment in the loop.
#
# NOTE for a project whose gates need a wrapper to reach its database (e.g. one that starts a local
# relay to a database on the network): invoke THIS SCRIPT under that wrapper.
# The gates and the teardown are children of this process, so wrapping the script wraps both; passing
# a wrapped --gates string leaves the teardown unwrapped and leaks the worktree database.
# The lock is released on EVERY exit path except 10 (it is not ours to release).
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile.
set -uo pipefail

wt=""; msgfile=""; gates=""; extra=""; teardown=""; refresh=""; trunk=""; attempts=3
lock_wait=${LAND_LOCK_WAIT_MINUTES:-30}
while [ $# -gt 0 ]; do
  case "$1" in
    --message-file) msgfile=$2; shift 2 ;;
    --gates) gates=$2; shift 2 ;;
    --extra-gate) extra="$extra && $2"; shift 2 ;;
    --teardown) teardown=$2; shift 2 ;;
    --refresh) refresh=$2; shift 2 ;;
    --trunk) trunk=$2; shift 2 ;;
    --attempts) attempts=$2; shift 2 ;;
    --lock-wait) lock_wait=$2; shift 2 ;;
    -*) echo "unknown flag $1" >&2; exit 64 ;;
    *) wt=$1; shift ;;
  esac
done
[ -n "$wt" ] && [ -d "$wt" ] || { echo "usage: land.sh <worktree-path> --message-file <file> [flags]" >&2; exit 64; }
[ -n "$msgfile" ] && [ -s "$msgfile" ] || { echo "--message-file is required and must be non-empty" >&2; exit 64; }
# Absolute, because the commit below runs with the WORKTREE as its cwd: a relative path would be read
# relative to the worktree and fail after the `reset --soft`, leaving the branch squashed but
# uncommitted.
case "$msgfile" in /*) ;; *) msgfile="$PWD/$msgfile" ;; esac
[ -n "$gates" ] || { echo "--gates is required: pass the project declaration's full gate line" >&2; exit 64; }
wt=$(cd "$wt" && pwd)

common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a worktree" >&2; exit 65; }
repo=$(dirname "$common")
[ "$repo" != "$wt" ] || { echo "$wt is the main checkout, not a worktree" >&2; exit 65; }
[ -n "$trunk" ] || trunk=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=main
branch=$(git -C "$wt" symbolic-ref --short HEAD) || { echo "worktree is not on a branch" >&2; exit 65; }

lock="$repo/.claude/land.lock"
mkdir -p "$repo/.claude"
held_lock=0
release() { [ "$held_lock" = 1 ] && rm -rf "$lock"; }
trap release EXIT

# The cockpit this landing belongs to: its registry `name` for the waiter's message, and its
# `sessionId` so skills/dispatch/wait-for.sh can name the holder of a wait on this lock — never for
# liveness, which is pid + start time below. Walk up to the `claude` ancestor and read that pid's
# entry in Claude Code's session registry. Best-effort: an unresolvable session is not an error.
owner_session() {   # <jq field>
  p=$$ ; n=0
  while [ "$n" -lt 8 ] && [ "${p:-1}" -gt 1 ]; do
    f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$p.json"
    if [ -f "$f" ]; then jq -r ".$1 // empty" "$f" 2>/dev/null; return; fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') ; n=$((n + 1))
  done
}
# A pid is reused; a pid whose process started at the recorded moment is not.
pid_started() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }   # C locale: the lock owner and its reader may run under different LANGs
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$(pid_started "$1")" = "$2" ]; }

lock_started=$(date +%s); reported=""; ownerless_since=""
while :; do
  if mkdir "$lock" 2>/dev/null; then
    { echo "pid=$$"; echo "started=$(pid_started $$)"; echo "branch=$branch"
      echo "session=$(owner_session name)"; echo "session_id=$(owner_session sessionId)"; echo "since=$(date -u +%FT%TZ)"; } > "$lock/owner"
    held_lock=1
    [ -z "$reported" ] || echo "==> lock acquired after $(( ($(date +%s) - lock_started) / 60 ))m"
    break
  fi

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

  waited=$(( ($(date +%s) - lock_started) / 60 ))
  if [ "$waited" -ge "$lock_wait" ]; then
    echo "the lock on ${l_branch:-?}${l_session:+ ($l_session)} did not clear in ${waited}m" >&2
    echo "and its process (pid $l_pid) is still alive: that landing is stuck, not busy." >&2
    echo "This branch is untouched — land it once the other one is resolved." >&2
    exit 10
  fi
  if [ "$reported" != "$l_pid" ]; then   # once per holder: a second landing may take it before us
    echo "==> land.lock held by ${l_branch:-another landing} (pid $l_pid${l_session:+, $l_session}) — waiting up to ${lock_wait}m"
    reported=$l_pid
  fi
  sleep 30
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
  # reporting "trunk moved", which is the opposite of what happened.
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
  if [ -z "$refresh" ] && [ -x "$repo/.claude/scripts/dispatch/worktree-refresh.sh" ]; then
    refresh="\"$repo/.claude/scripts/dispatch/worktree-refresh.sh\" \"$wt\""
  fi
  if [ -n "$refresh" ]; then
    echo "==> refresh the worktree for its new base: $refresh"
    if ! (cd "$wt" && eval "$refresh"); then echo "worktree refresh failed after rebase" >&2; exit 21; fi
  fi
  echo "==> gates: $gates$extra"
  if ! (cd "$wt" && eval "$gates$extra"); then echo "gates red after rebase" >&2; exit 21; fi
  echo "==> fast-forward $trunk in the main checkout"
  git -C "$repo" checkout -q "$trunk" 2>/dev/null
  if git -C "$repo" merge -q --ff-only "$branch"; then break; fi
  # The trunk still an ancestor of the branch means a fast-forward WAS possible: what refused it is
  # the main checkout's own uncommitted paths in the way. Retrying cannot fix that, and calling it
  # "trunk moved" would send the model chasing the wrong cause — exit 26 so /land can ask
  # wait-for.sh whose paths they are.
  if git -C "$repo" merge-base --is-ancestor "$trunk" "$branch" && [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "fast-forward refused by uncommitted paths in the main checkout — branch rebased and green, left as it is:" >&2
    git -C "$repo" status --porcelain | sed 's/^/  /' >&2
    exit 26
  fi
  echo "fast-forward refused — $trunk moved during the gates; retrying" >&2
  [ "$i" -lt "$attempts" ] || exit 23
done

echo "==> push"
git -C "$repo" push -q origin "$trunk" || exit 22
hash=$(git -C "$repo" rev-parse --short HEAD)
subject=$(git -C "$repo" log -1 --format=%s)

echo "==> tear down, then remove — in that order"
if [ -z "$teardown" ] && [ -x "$repo/.claude/scripts/dispatch/worktree-teardown.sh" ]; then
  teardown="\"$repo/.claude/scripts/dispatch/worktree-teardown.sh\" \"$wt\""
fi
if [ -n "$teardown" ]; then
  (cd "$wt" && eval "$teardown") || echo "WARN: per-worktree teardown failed — continuing the landing (gc will sweep)" >&2
fi
git -C "$repo" worktree remove --force "$wt" || echo "WARN: worktree remove failed: $wt" >&2
git -C "$repo" branch -d "$branch" || echo "WARN: branch -d refused for $branch (not merged?)" >&2

echo "LANDED $hash $subject"
exit 0
