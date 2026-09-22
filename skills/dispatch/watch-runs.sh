#!/bin/bash
# One-shot health poll over dispatched implementation runs. Prints one line per finding and exits.
#
# WHY THIS EXISTS: `claude agents` is the observability pane and it is enough — when you look at it.
# The failure mode is not looking. Measured, in one afternoon: two runs sat parked 57 and 67 minutes
# on a `Monitor` permission prompt no rule covered, and a third finished, landed, and freed its
# worktree without anyone noticing either event. Dispatched runs are launched with
# `--permission-mode bypassPermissions` now, so parking is far less likely — but "less likely" is not
# "impossible", and silence and unlanded branches were never covered by the permission fix at all.
#
# Called each tick by the cockpit's `/loop`. Report-only by design: it never kills a run and never
# lands a branch. Landing stays driven by the plan's `## Handoff`, so that one operator decision has
# exactly one owner.
#
# Prefixes are stable and greppable — the loop diffs them between ticks and reports only changes:
#   BLOCKED  a live run is waiting on a permission prompt (with the tool it is stuck on)
#   STALLED  a run reports busy but its transcript has not moved in $STALL_MIN minutes
#   ORPHAN   a worktree holds work but no live session owns it — nothing is driving it
#   UNLANDED a branch is ahead of the trunk and needs /land
#   RUNNING  healthy, working, transcript moving
# A Remote Control run also reports idle in the gap between launch and the send that gives it its
# plan, so "idle with no commits and nothing dirty" is reported apart from a genuinely finished run.
#   QUIET    no dispatched runs and no unlanded branches
#
# PORTABILITY: this lives next to the skill that calls it, not in any project, so every project the
# pipeline touches gets it with no per-repo copy to drift. Nothing here is project-specific — the repo
# root, trunk, and worktrees are all discovered from git. Two knobs, both env vars:
#   STALL_MIN          minutes of transcript silence before a busy run counts as stalled (15)
#   WT_BRANCH_PREFIX   the refs/heads/<prefix> namespace /dispatch creates branches in (wt)
#
#   watch-runs.sh [--mine "<tag>-<hex>"]                      one-shot: print findings, exit
#   watch-runs.sh --watch [--mine KEY] [--interval 60] [--max-min 30] [--state FILE]
#
# --watch moves the TICKING out of the model. It loops on its own clock and returns only when the
# normalized finding set differs from the previous tick — so a wave that is simply working costs the
# cockpit nothing, and BLOCKED/STALLED/UNLANDED reach it within one interval instead of within one
# `/loop` tick. Measured 2026-09-22 over 7 days: the per-minute `/loop` spelling cost 2,187 cockpit
# turns and 421M cache-read tokens to report "no change" on almost every one of them.
# Run it detached (`Bash` with run_in_background); the harness re-invokes the cockpit when it exits.
#
# --mine makes "watch your own runs only" structural instead of a rule the caller re-applies on every
# tick. Its argument is the cockpit's PAIRING KEY, not its name: /dispatch names a cockpit
# `<tag>-<hex> · <human title>` and each of its runs `<tag>-<hex> · impl <slug>`, so the shared
# leading key is what makes them a pair in a list that truncates the end of every name. Pass the key
# alone (`ln-de`) and a run belonging to another cockpit is dropped entirely.
# Anything not attributable to a cockpit is still reported: a session whose name does not follow the
# pattern (hand-started), and the repo-global findings (ORPHAN, FOREIGN, a branch whose worktree is
# gone) which belong to no session by definition.
#
# Written for macOS /bin/bash 3.2: no `mapfile`, no arrays under `set -u`.
set -uo pipefail

STALL_MIN=${STALL_MIN:-15}
WT_BRANCH_PREFIX=${WT_BRANCH_PREFIX:-wt}
mine=""
watch=0
interval=${WATCH_INTERVAL:-60}
max_min=${WATCH_MAX_MIN:-30}
state_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mine) mine=$2; shift 2 ;;
    --watch) watch=1; shift ;;
    --interval) interval=$2; shift 2 ;;
    --max-min) max_min=$2; shift 2 ;;
    --state) state_file=$2; shift 2 ;;
    -*) echo "ERROR unknown flag $1"; exit 0 ;;
    *) shift ;;
  esac
done
# The MAIN checkout, not "wherever I was run from". `--show-toplevel` answers the latter, so calling
# this from inside a worktree used to report the main checkout as if it were a dispatched run. Derive
# it from the common git dir instead, which every worktree shares: <main>/.git -> <main>.
common=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "ERROR not a git repo"; exit 0; }
case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
repo=$(cd "$(dirname "$common")" 2>/dev/null && pwd) || { echo "ERROR cannot resolve repo root"; exit 0; }
trunk=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=$(git -C "$repo" config --get init.defaultBranch 2>/dev/null)
[ -n "$trunk" ] || trunk=main

agents=$(claude agents --json 2>/dev/null)
[ -n "$agents" ] || agents='[]'
now=$(date +%s)

# A session's transcript path: the project dir is its cwd with every "/" turned into "-". Glob every
# profile root ($HOME/.claude*), because this machine runs several (.claude-work, .claude-personal) and
# a run's transcript lives under whichever profile dispatched it.
transcript_for() {
  munged=$(printf '%s' "$1" | tr '/' '-')
  for base in "$HOME"/.claude*/projects; do
    [ -f "$base/$munged/$2.jsonl" ] && { printf '%s\n' "$base/$munged/$2.jsonl"; return; }
  done
}

# Is ANYTHING driving this worktree? `claude agents` cannot answer that: its registry is per profile,
# so a wave dispatched under .claude-work is invisible to a poll under .claude-personal, and a cloud
# session is invisible to both. Measured: a healthy two-run wave reported ORPHAN when polled from the
# wrong profile, and a run that had in fact finished and landed was called dead because no local
# process backed it. So ask the OS instead — a live process whose cwd is the worktree, or a transcript
# under ANY profile that moved recently. Both are true regardless of which profile is asking.
driven() {
  lsof -a -d cwd -c claude -Fn 2>/dev/null | grep -qx "n$1" && return 0
  munged=$(printf '%s' "$1" | tr '/' '-')
  newest=0
  for f in "$HOME"/.claude*/projects/"$munged"/*.jsonl; do
    [ -f "$f" ] || continue
    m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$newest" ] && newest=$m
  done
  [ "$newest" = "0" ] && return 1
  [ $(( (now - newest) / 60 )) -lt "$STALL_MIN" ]
}

# Last tool a session tried — the thing a BLOCKED run is stuck on. jq reads the tail as a stream.
last_tool() {
  tail -6 "$1" 2>/dev/null \
    | jq -r 'select(.message?.content? | type == "array") | .message.content[]
             | select(.type == "tool_use") | .name' 2>/dev/null | tail -1
}

# Both loops below run in pipeline subshells, so a counter set inside them never reaches this shell.
# Collect their output instead and decide QUIET from whether anything was reported — otherwise a
# stranded branch with no worktrees prints UNLANDED *and* QUIET, contradicting itself in the one case
# this script exists to catch.
report() {


# Every worktree of this repo except the main checkout: that is where dispatched runs live.
git -C "$repo" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  [ "$wt" = "$repo" ] && continue
  # Prefer the checked-out branch minus its namespace; fall back to the directory name for a
  # worktree that does not follow the pipeline's naming (a hand-made one, or another tool's).
  slug=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null | sed "s#^$WT_BRANCH_PREFIX/##")
  [ -n "$slug" ] || slug=$(basename "$wt" | sed "s/^.*-$WT_BRANCH_PREFIX-//")

  ahead=$(git -C "$wt" rev-list --count "$trunk"..HEAD 2>/dev/null) || ahead=0
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  # The live session owning this worktree, if any.
  row=$(printf '%s' "$agents" | jq -c --arg wt "$wt" '.[] | select(.cwd == $wt)' 2>/dev/null | head -1)

  if [ -z "$row" ]; then
    # Not in THIS profile's registry. Work present = something to account for; empty = a leftover shell.
    if [ "$ahead" != "0" ] || [ "$dirty" != "0" ]; then
      if driven "$wt"; then
        echo "FOREIGN  $slug  +$ahead commits, $dirty dirty — driven from another profile or the cloud, not by this one"
      else
        echo "ORPHAN   $slug  +$ahead commits, $dirty dirty — nothing is driving it, needs /land or a restart"
      fi
    fi
    continue
  fi

  # --mine: drop a run that demonstrably belongs to another cockpit. An unparseable name is kept —
  # reporting a hand-started session is noise, missing one is a run nobody owns.
  if [ -n "$mine" ]; then
    aname=$(printf '%s' "$row" | jq -r '.name // empty')
    # `${mine}` braced deliberately: bash 3.2 reads `$mine·` as a variable named `mine\xc2` and
    # dies with "unbound variable", because it swallows the separator's first UTF-8 byte.
    case "$aname" in
      ("${mine} · "*|"${mine}·"*|"impl: ${mine} · "*) ;;  # mine — current shape, or an older one
      (*" · impl "*|*"·"*) continue ;;                    # another cockpit's run
      (*) ;;                                              # not a dispatched run at all — keep
    esac
  fi

  status=$(printf '%s' "$row" | jq -r '.status // "-"')
  state=$(printf '%s' "$row" | jq -r '.state // "-"')
  waiting=$(printf '%s' "$row" | jq -r '.waitingFor // empty')
  sid=$(printf '%s' "$row" | jq -r '.sessionId // empty')
  tr_file=$(transcript_for "$wt" "$sid")

  idle_min=-1
  if [ -n "$tr_file" ]; then
    mtime=$(stat -f %m "$tr_file" 2>/dev/null || echo "$now")
    idle_min=$(( (now - mtime) / 60 ))
  fi

  # A Remote Control run reads "idle" twice: once when /deliver has finished, and once in the window
  # between launch and the SendMessage that hands it the plan (§4). Only the first is UNLANDED. The
  # second is the failure mode this design introduces — a session launched and then never given its
  # plan sits at an empty prompt box looking exactly like a finished one, so separate them by whether
  # any work exists, and escalate a young empty session to STALLED once the send is clearly overdue.
  if { [ "$status" = "idle" ] || [ "$state" = "done" ]; } \
     && [ -z "$waiting" ] && [ "$ahead" = "0" ] && [ "$dirty" = "0" ]; then
    if [ "$idle_min" -ge "$STALL_MIN" ]; then
      echo "STALLED  $slug  idle ${idle_min}m with nothing committed — was its plan ever sent?"
    else
      echo "RUNNING  $slug  up and idle, waiting for its plan"
    fi
    continue
  fi

  if [ "$state" = "blocked" ] || [ -n "$waiting" ]; then
    echo "BLOCKED  $slug  waiting on ${waiting:-a prompt} at tool '$(last_tool "$tr_file")' — parked ${idle_min}m"
  elif [ "$status" = "busy" ] && [ "$idle_min" -ge "$STALL_MIN" ]; then
    echo "STALLED  $slug  reports busy but silent ${idle_min}m (threshold ${STALL_MIN}m), last tool '$(last_tool "$tr_file")'"
  elif [ "$status" = "idle" ] || [ "$state" = "done" ]; then
    echo "UNLANDED $slug  run finished, +$ahead commits, $dirty dirty — ready for /land"
  else
    echo "RUNNING  $slug  $status/$state, +$ahead commits, active ${idle_min}m ago"
  fi
done

# Branches ahead of the trunk whose worktree is already gone — the stranding this pipeline exists to
# prevent. A finished 33-commit feature was once lost exactly here.
git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/$WT_BRANCH_PREFIX" | while read -r b; do
  n=$(git -C "$repo" rev-list --count "$trunk".."$b" 2>/dev/null) || continue
  [ "$n" = "0" ] && continue
  git -C "$repo" worktree list --porcelain | grep -q "^branch refs/heads/$b$" && continue
  echo "UNLANDED $b  +$n commits, no worktree — /land it or delete it deliberately"
done

}

# Re-read the two globals `report` closes over. They are sampled at file scope for the one-shot
# path; a watch tick must resample them or every tick reports the launch-time snapshot forever.
resample() {
  now=$(date +%s)
  agents=$(claude agents --json 2>/dev/null)
  [ -n "$agents" ] || agents='[]'
}

once() {
  out=$(report)
  [ -n "$out" ] || out="QUIET    no dispatched runs, nothing unlanded"
  printf '%s\n' "$out"
}

# The wake signature. Two transforms, both load-bearing:
#   sort  — `git worktree list` order is not stable across ticks, and a reordered but identical set
#           is not a change.
#   digits→N — every line carries a counter that moves on its own (elapsed minutes, commit count,
#           dirty count). Left in, they differ on almost every tick and the watcher degenerates into
#           the per-minute poll it replaces. Cost: two slugs differing only in a digit hash alike;
#           they remain separate LINES, so the set still differs whenever both are present.
signature() { printf '%s\n' "$1" | sed 's/[0-9][0-9]*/N/g' | sort; }

if [ "$watch" = 0 ]; then
  once
  exit 0
fi

# ── watch mode ────────────────────────────────────────────────────────────────────
# Blocks OUT OF THE MODEL, ticking on its own clock, and returns only when the picture changes.
# Run it detached (`Bash` with run_in_background) — the harness re-invokes the cockpit on exit.
#
# The wake rule is ONE comparison: the normalized finding set differs from the last tick's. That is
# sufficient because the ALARM states are computed by `report` itself from elapsed time — a run that
# goes silent crosses STALL_MIN and a STALLED line APPEARS, which is a set change. So "nothing is
# happening" and "nothing has happened for too long" reach the cockpit through the same door, and no
# second timer is needed.
#
# The state file persists ACROSS invocations on purpose: re-arming the watcher while a run is still
# BLOCKED must not fire instantly again. Only a genuinely new picture wakes the cockpit.
# Keyed by REPO as well as cockpit. One profile dispatches for several repos (.claude-personal drives
# ml-billing and rtu), so a key built from `--mine` alone collides: two watchers share one file, each
# reads the other's findings as its baseline, and they wake each other every tick — strictly worse
# than the poll this replaces. Omitting `--mine` made that collision certain, since the key was "all".
[ -n "$state_file" ] || {
  dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/dispatch-runs"
  mkdir -p "$dir" 2>/dev/null
  safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
  state_file="$dir/.watch-$(safe "$(basename "$repo")")-$(safe "${mine:-all}")"
}

started=$(date +%s)
first=1
while :; do
  resample
  out=$(once)
  sig=$(signature "$out")

  if [ "$first" = 1 ] && [ ! -f "$state_file" ]; then
    # No baseline yet: capture it silently. Waking on "I just started looking" is not an event.
    printf '%s\n' "$sig" > "$state_file"
  else
    prev=$(cat "$state_file" 2>/dev/null || true)
    if [ "$sig" != "$prev" ]; then
      printf '%s\n' "$sig" > "$state_file"
      echo "WAKE     state changed"
      printf '%s\n' "$out"
      exit 0
    fi
  fi
  first=0

  case "$out" in
    QUIET*) echo "WAKE     quiet — nothing dispatched, nothing unlanded"; printf '%s\n' "$out"; exit 0 ;;
  esac

  if [ $(( ($(date +%s) - started) / 60 )) -ge "$max_min" ]; then
    # Bounded on purpose: a watcher that outlives its cockpit is a zombie holding a stale baseline.
    # Hand the decision back instead of running forever.
    echo "WAKE     heartbeat — ${max_min}m with no change, re-arm or stop"
    printf '%s\n' "$out"
    exit 0
  fi
  sleep "$interval"
done
