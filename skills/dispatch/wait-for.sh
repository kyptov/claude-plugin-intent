#!/bin/bash
# Wait-for records and the cycle check: a session blocked by ANOTHER session (a landing in flight,
# that session's main-checkout lease, its unlanded branch, its uncommitted paths) gets a verdict
# from this script, never a question to the operator. The operator is the one participant with no
# global view, so asking them "wait for the other session?" from both sides is how two cockpits
# deadlocked: each waited on the other and the operator agreed both times.
#
#   wait-for.sh check --resource <r> [flags]   one verdict; on WAIT, writes this session's record
#   wait-for.sh wait  --resource <r> [flags]   the same check every 15s until it is not WAIT; run it
#                                              detached — its exit is what wakes the session
#   wait-for.sh clear [--self <sid>]           delete this session's record (dispatched, or gave up)
#   wait-for.sh list                           every live record, one line each
#
#   <r>: land-lock | lease | branch <name> | dirty-checkout   (one argument: "branch wt/foo")
#   flags: --self <session-id>      default: CLAUDE_PID's entry in the session registry, else the
#                                   nearest ancestor process that has one
#          --lease <path>           the project's main-checkout lease file, as its declaration names it;
#                                   first line `<session-id> <epoch of last write>`. Omit if none.
#          --lease-idle <minutes>   a lease idle this long is stale and takeable (default 45)
#          --lock <dir>             the land lock land.sh takes (default .claude/land.lock)
#          --trunk <branch>         default origin/HEAD, else main
#          --max-wait <minutes>     `wait` gives up after this long (default 100: under the 2h ceiling
#                                   of a background Bash call, so the give-up is ours, not a kill)
#
# Verdict — the first stdout line is `VERDICT <word> …`; skills route on the word, never re-derive it:
#   CLEAR  0   nothing another session holds blocks this one any more (on a non-zero preflight exit
#              this means the helper just removed a dead session's lease: re-run the preflight)
#   WAIT   30  a live session holds it and no cycle runs back to us. The record is written; the next
#              line, `WAIT-CMD …`, is the exact `wait` command to run detached.
#   YIELD  31  a cycle runs back to us and we are its victim: what we held is released (or, for
#              uncommitted paths, listed for the operator to commit or stash) and our record is gone.
#              The caller does NOT proceed: no dispatch, no landing. It reports the yield and stops.
#   FIX    32  no live session holds the block, so waiting can never clear it: a branch whose
#              cockpit is gone, uncommitted paths nobody live owns or that are our own, a session we
#              cannot resolve. The caller acts per its own exit code.
#   TIMEOUT 33 (`wait` only) --max-wait ran out; the record is gone. Report it, plainly.
#   64 usage · 65 not a git repo
#
# Who holds what — every holder is a session id, the one Claude Code's registry and hook payloads use:
#   land-lock       `session_id=` in <lock>/owner (land.sh writes it). A landing never holds and waits
#                   (land.sh takes one lock and nothing else), so a land-lock edge can't close a
#                   cycle: it is always WAIT, and the cycle walk stops at it.
#   lease           field 1 of the lease file — the project's guard hook writes the hook's session_id.
#   branch <name>   `git config branch.<name>.workflowSession`, set by the plugin's WorktreeCreate hook
#                   to the session that dispatched the run; `git branch -m` carries it to wt/<slug>.
#   dirty-checkout  the lease holder: the only session the project lets write source in the main
#                   checkout, so the only one those paths can be attributed to.
#
# Liveness is pid + start time, never pid alone (a pid is reused): the registry file
# $CLAUDE_CONFIG_DIR/sessions/<pid>.json carries `sessionId`, `procStart` (ps lstart IN UTC) and
# `startedAt` (epoch ms — the session's age). A record is junk, and is deleted on sight, when its
# session is not alive or its `updated=` is over 3 minutes old (a live `wait` refreshes it every tick,
# so a stale one belongs to a session that stopped waiting without saying so).
#
# Victim choice in a cycle: the YOUNGEST member that can release what the cycle needs from it. A
# lease can be dropped at once and uncommitted paths can be committed or stashed; an unlanded branch
# or a running landing cannot be released by yielding (only landing releases a branch — the very
# thing the waiter is waiting for), so its holder is not eligible. If nobody is eligible, the
# youngest member yields anyway: the cycle is then all branches, which clear as their runs land.
# Both sides compute the same victim from the same records, so they agree without talking.
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile; every `case` pattern carries a
# leading `(` because bash 3.2 mis-parses a bare `)` in a case nested inside `$( … )`.
set -uo pipefail

usage() { echo "usage: wait-for.sh check|wait|clear|list --resource <land-lock|lease|branch <name>|dirty-checkout> [--self <sid>] [--lease <path>] [--lease-idle <min>] [--lock <dir>] [--trunk <branch>] [--max-wait <min>]" >&2; exit 64; }

mode=${1:-}; [ $# -gt 0 ] && shift
case "$mode" in (check|wait|clear|list) ;; (*) usage ;; esac
self=""; resource=""; lease=""; lease_idle=45; lock=".claude/land.lock"; trunk=""; max_wait=100
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    (--self) self=$2 ;;
    (--resource) resource=$2 ;;
    (--lease) lease=$2 ;;
    (--lease-idle) lease_idle=$2 ;;
    (--lock) lock=$2 ;;
    (--trunk) trunk=$2 ;;
    (--max-wait) max_wait=$2 ;;
    (*) usage ;;
  esac
  shift 2
done
case "$resource" in
  (land-lock|lease|dirty-checkout) ;;
  ("branch "?*) ;;
  ("") case "$mode" in (check|wait) usage ;; esac ;;
  (*) usage ;;
esac

# The same answer from a worktree as from the main checkout: records, locks and the lease all live in
# the main checkout, which is the parent of the COMMON git dir.
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git repo" >&2; exit 65; }
repo=$(dirname "$common")
# Before the cd below: $0 may be relative to the caller's directory.
here=$(cd "$(dirname "$0")" && pwd)
cd "$repo" || exit 65
[ -n "$trunk" ] || trunk=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=main
# Tests point this at a fixture registry; in a session it is Claude Code's own.
sessions=${WAITFOR_SESSIONS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions}
waits="$repo/.claude/waits"
tab=$(printf '\t')
now() { date +%s; }

# --- sessions -------------------------------------------------------------------------------------
# `born<TAB>name<TAB>pid` of the LIVE process carrying this session id; fails when none is alive. A
# crashed session leaves its registry file behind, so a file alone proves nothing: its pid must be
# running AND have started at the recorded instant. procStart is written in UTC, hence TZ=UTC.
session_live() {
  [ -n "$1" ] && [ -d "$sessions" ] || return 1
  jq -r --arg s "$1" 'select(.sessionId == $s) | [.pid, .procStart, .startedAt, (.name // "")] | @tsv' \
    "$sessions"/*.json 2>/dev/null \
  | while IFS="$tab" read -r pid ps0 born name; do
      [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
      [ "$(TZ=UTC ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//;s/ *$//')" = "$ps0" ] || continue
      printf '%s\t%s\t%s\n' "$born" "$name" "$pid"
      break
    done | grep .   # the loop is a subshell: an empty output is how "not alive" reaches the caller
}
born_of() { session_live "$1" | cut -f1; }
label() { n=$(session_live "$1" | cut -f2); echo "$1${n:+ ($n)}"; }

if [ -z "$self" ]; then
  # CLAUDE_PID names the session's own process in its Bash tool; failing that, walk up to the first
  # ancestor with a registry entry (a script run from a hook or a nested shell).
  if [ -n "${CLAUDE_PID:-}" ] && [ -f "$sessions/$CLAUDE_PID.json" ]; then
    self=$(jq -r '.sessionId // empty' "$sessions/$CLAUDE_PID.json" 2>/dev/null)
  else
    p=$$; n=0
    while [ -z "$self" ] && [ "$n" -lt 12 ] && [ "${p:-1}" -gt 1 ]; do
      [ -f "$sessions/$p.json" ] && self=$(jq -r '.sessionId // empty' "$sessions/$p.json" 2>/dev/null)
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); n=$((n + 1))
    done
  fi
fi

# --- records --------------------------------------------------------------------------------------
field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }

# Succeeds (and prints the file) only for a record that still describes a live wait; deletes junk.
live_record() {
  f="$waits/$1"
  [ -f "$f" ] || return 1
  u=$(field updated "$f")
  if ! session_live "$1" >/dev/null || [ $(( $(now) - ${u:-0} )) -gt 180 ]; then
    rm -f "$f"; return 1
  fi
  echo "$f"
}

write_record() {   # holder resource
  mkdir -p "$waits"
  # Records are per-machine state, never content: keep them out of `git status`, or the dirty-checkout
  # check would read our own record as uncommitted work and block on itself.
  grep -qsxF '.claude/waits/' "$common/info/exclude" \
    || { mkdir -p "$common/info" && echo '.claude/waits/' >> "$common/info/exclude"; }
  me=$(session_live "$self")
  # Keep the first `since` across refreshes, so `list` shows how long the wait has really lasted.
  since=$(field since "$waits/$self"); [ -n "$since" ] || since=$(date -u +%FT%TZ)
  tmp="$waits/.$self.$$"
  { echo "holder=$1"; echo "resource=$2"; echo "started=$(echo "$me" | cut -f1)"
    echo "pid=$(echo "$me" | cut -f3)"; echo "since=$since"; echo "updated=$(now)"; } > "$tmp"
  mv "$tmp" "$waits/$self"   # rename is atomic: a reader never sees half a record
}
drop_record() { [ -n "$self" ] && rm -f "$waits/$self"; }

# --- the block as it stands now -------------------------------------------------------------------
lease_holder() {   # field 1 of the lease file, whatever its age
  [ -n "$lease" ] && [ -f "$lease" ] && awk 'NR==1{print $1}' "$lease"
}
# Prints the holder's session id (or `pid:<n>` for a landing whose lock names no session); exit 1 =
# the resource is no longer held at all.
resolve() {
  case "$resource" in
    (land-lock)
      [ -e "$lock" ] || return 1
      l_pid=$(field pid "$lock/owner"); l_start=$(field started "$lock/owner")
      # land.sh's own rule, in its own terms (it writes `started` from a local-time lstart): a lock
      # whose process is gone is taken over by the next landing, so it blocks nobody.
      if [ -n "$l_pid" ]; then
        kill -0 "$l_pid" 2>/dev/null && [ "$(ps -o lstart= -p "$l_pid" 2>/dev/null | sed 's/^ *//;s/ *$//')" = "$l_start" ] || return 1
      fi
      sid=$(field session_id "$lock/owner")
      echo "${sid:-pid:${l_pid:-?}}" ;;
    (lease)
      [ -n "$lease" ] && [ -f "$lease" ] || return 1
      ts=$(awk 'NR==1{print $2}' "$lease")
      # The guard hook's own staleness rule: an idle lease is takeable, so it is no block.
      [ $(( ($(now) - ${ts:-0}) / 60 )) -lt "$lease_idle" ] || return 1
      h=$(lease_holder)
      [ "$h" != "$self" ] || return 1   # our own lease never blocks us
      echo "$h" ;;
    (branch*)
      b=${resource#branch }
      git show-ref --verify --quiet "refs/heads/$b" || return 1
      [ "$(git rev-list --count "$trunk..$b" 2>/dev/null || echo 0)" != 0 ] || return 1
      git config --get "branch.$b.workflowSession"
      return 0 ;;
    (dirty-checkout)
      [ -n "$(git status --porcelain)" ] || return 1
      lease_holder
      return 0 ;;
  esac
}

# Walks records from the holder. Iff the chain comes back to us, prints one `<sid>|<resource>` line
# per cycle member — the resource that member is waited on for — starting with ourselves.
walk() {   # holder my-resource
  cur=$1; into=$2; lines=""; seen=" $self "; hops=0
  while [ "$hops" -lt 16 ]; do
    lines="$lines$cur|$into
"
    f=$(live_record "$cur") || return 1
    r_res=$(field resource "$f"); r_hold=$(field holder "$f")
    # A running landing waits on nothing, so no cycle passes through a land-lock edge.
    [ "$r_res" != land-lock ] || return 1
    if [ "$r_hold" = "$self" ]; then
      printf '%s|%s\n%s' "$self" "$r_res" "$lines"
      return 0
    fi
    # A cycle that does not run through us is not ours to break — its own members will.
    case "$seen" in (*" $r_hold "*) return 1 ;; esac
    seen="$seen$cur "; into=$r_res; cur=$r_hold; hops=$((hops + 1))
  done
  return 1
}

# The member that yields: youngest eligible (waited on for a lease or uncommitted paths), else youngest.
victim() {   # cycle lines `sid|resource-it-is-waited-on-for`
  printf '%s\n' "$1" | while IFS='|' read -r sid res; do
    [ -n "$sid" ] || continue
    case "$res" in (lease|dirty-checkout) el=1 ;; (*) el=0 ;; esac
    echo "$el $(born_of "$sid") $sid"
  done | sort -k1,1nr -k2,2nr -k3,3r | head -1 | cut -d' ' -f3
}

paths() { git status --porcelain | sed 's/^/          /'; }

# --- one evaluation; prints the verdict and returns its code ----------------------------------------
evaluate() {
  if ! holder=$(resolve); then
    drop_record
    echo "VERDICT CLEAR — $resource is no longer held"
    return 0
  fi
  if [ -z "$self" ] || ! session_live "$self" >/dev/null; then
    echo "VERDICT FIX — this session is not in the registry (${self:-no id}), so no wait can be recorded or checked; act on the block itself"
    return 32
  fi
  case "$holder" in
    (pid:*)
      # A landing from a land.sh too old to record its session: it still finishes on its own.
      write_record "$holder" "$resource"
      echo "VERDICT WAIT holder=$holder resource=$resource — a landing in flight; it releases on its own"
      echo "WAIT-CMD $wait_cmd"
      return 30 ;;
    ("")
      drop_record
      echo "VERDICT FIX — no session is recorded as holding $resource, so waiting cannot clear it"
      [ "$resource" != dirty-checkout ] || { echo "        uncommitted in the main checkout — commit or stash:"; paths; }
      return 32 ;;
  esac
  if [ "$holder" = "$self" ]; then
    drop_record
    echo "VERDICT FIX — $resource is held by this session itself"
    [ "$resource" != dirty-checkout ] || { echo "        uncommitted in the main checkout — commit or stash:"; paths; }
    return 32
  fi
  if ! session_live "$holder" >/dev/null; then
    drop_record
    if [ "$resource" = lease ] && [ "$(lease_holder)" = "$holder" ]; then
      # A dead session's lease is junk the guard hook would otherwise honour until it idles out —
      # the same takeover land.sh does for a dead landing's lock.
      rm -f "$lease"
      echo "VERDICT CLEAR — lease holder $holder is not a live session; removed its lease ($lease)"
      return 0
    fi
    echo "VERDICT FIX — $resource is held by $holder, which is not a live session; waiting cannot clear it"
    [ "$resource" != dirty-checkout ] || { echo "        uncommitted in the main checkout — commit or stash:"; paths; }
    return 32
  fi

  write_record "$holder" "$resource"
  if [ "$resource" = land-lock ] || ! cycle=$(walk "$holder" "$resource"); then
    echo "VERDICT WAIT holder=$(label "$holder") resource=$resource — no wait cycle"
    echo "WAIT-CMD $wait_cmd"
    return 30
  fi
  ring=$(printf '%s\n' "$cycle" | cut -d'|' -f1 | while read -r s; do printf '%s -> ' "$(label "$s")"; done)
  ring="$ring$(label "$self")"
  v=$(victim "$cycle")
  if [ "$v" != "$self" ]; then
    echo "VERDICT WAIT holder=$(label "$holder") resource=$resource — wait cycle $ring; $(label "$v") yields (younger), keep waiting"
    echo "WAIT-CMD $wait_cmd"
    return 30
  fi

  # We yield. What the cycle needs from us is what our predecessor in the ring waits on us for.
  mine=$(printf '%s\n' "$cycle" | head -1 | cut -d'|' -f2)
  waiter=$(printf '%s\n' "$cycle" | sed -n '$p' | cut -d'|' -f1)
  drop_record
  echo "VERDICT YIELD to=$(label "$waiter") — yielded to $(label "$waiter") to break a wait cycle: $ring"
  case "$mine" in
    (lease)
      # Only our own line: never delete a lease someone else has taken since.
      if [ "$(lease_holder)" = "$self" ]; then rm -f "$lease"; echo "        released: the main-checkout lease ($lease)"
      else echo "        released: nothing — the lease is no longer ours"; fi ;;
    (dirty-checkout)
      echo "        released: nothing yet — these uncommitted paths are what $(label "$waiter") waits on; the operator commits or stashes them:"
      paths ;;
    (*) echo "        released: this wait (an unlanded branch is released only by landing it)" ;;
  esac
  echo "        this session does not proceed: no dispatch, no landing for this target"
  return 31
}

# The exact command `wait` needs, so a skill runs it verbatim instead of rebuilding it.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
wait_cmd="$(q "$here/wait-for.sh") wait --self $(q "$self") --resource $(q "$resource") --lock $(q "$lock") --lease-idle $lease_idle --trunk $(q "$trunk") --max-wait $max_wait"
[ -z "$lease" ] || wait_cmd="$wait_cmd --lease $(q "$lease")"

case "$mode" in
  (clear) drop_record; exit 0 ;;
  (list)
    [ -d "$waits" ] || exit 0
    for f in "$waits"/*; do
      [ -f "$f" ] || continue
      s=$(basename "$f")
      live_record "$s" >/dev/null || continue
      echo "$(label "$s") waits on $(label "$(field holder "$f")") for $(field resource "$f") since $(field since "$f")"
    done
    exit 0 ;;
  (check) evaluate; exit $? ;;
  (wait)
    # A wait that is killed (the session ended, the tool call was stopped) must not leave a record
    # behind for another session to build a cycle out of.
    trap drop_record EXIT
    start=$(now)
    while :; do
      out=$(evaluate); rc=$?
      if [ "$rc" != 30 ]; then echo "$out"; exit "$rc"; fi
      if [ $(( ($(now) - start) / 60 )) -ge "$max_wait" ]; then
        echo "VERDICT TIMEOUT — waited ${max_wait}m on $resource; $(echo "$out" | head -1 | sed 's/^VERDICT WAIT //')"
        exit 33
      fi
      sleep "${WAITFOR_TICK:-15}"
    done ;;
esac
