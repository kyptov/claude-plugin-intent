#!/bin/bash
# Print the CURRENT name of the cockpit that dispatched this run — the address /deliver §7 sends to.
#
#   cockpit-addr.sh [worktree]      # default: this worktree's root
#
# A session name is NOT a stable address. `/dispatch` renames the cockpit by writing `name` +
# `nameSource: "explicit"` straight into `$CLAUDE_CONFIG_DIR/sessions/<pid>.json`, but the live
# cockpit process never reads that file back — it holds its own name state — so Claude Code's
# conversation auto-titler writes its own title over the rename within seconds.
#
# The run's own name is safe by contrast — it is born explicit (`claude -n`), so the titler skips it.
# Only the cockpit's is poked from outside, and only the cockpit's gets clobbered.
#
# So the address is resolved LATE, from something a rename cannot touch: the cockpit's sessionId,
# recorded by launch-run.sh at dispatch under $CLAUDE_CONFIG_DIR/dispatch-runs/<munged worktree>.
# Whatever the cockpit is called at the moment the run reports, that is what this prints.
#
# Deliberately NOT stored inside the worktree: the run commits its own tree, and a stray untracked
# file under .claude/ is one `git add -A` away from landing on the trunk.
#
# Exit 0 + the name on stdout. Exit 1 + a diagnostic on stderr when no live cockpit can be found —
# that is a real "nobody to report to", and /deliver §7 says so in its final report rather than
# guessing a name.
#
# Written for macOS /bin/bash 3.2.
set -uo pipefail

wt=${1:-}
if [ -z "$wt" ]; then
  wt=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo and no worktree given" >&2; exit 1; }
fi
wt=$(cd "$wt" 2>/dev/null && pwd -P) || { echo "no such worktree: $1" >&2; exit 1; }

profile=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
rec="$profile/dispatch-runs/$(printf '%s' "$wt" | tr '/' '-')"
[ -f "$rec" ] || { echo "no dispatch record for $wt (looked in $rec) — this run was not started by launch-run.sh, or it was started under a different profile" >&2; exit 1; }

sid=""; pid=""; key=""; at_launch=""
while IFS='=' read -r k v; do
  case "$k" in
    session_id) sid=$v ;;
    pid) pid=$v ;;
    key) key=$v ;;
    name_at_launch) at_launch=$v ;;
  esac
done < "$rec"

agents=$(claude agents --json 2>/dev/null)
[ -n "$agents" ] || agents='[]'

# 1. sessionId — immutable for the life of the session, and never recycled.
name=$(printf '%s' "$agents" | jq -r --arg s "$sid" 'map(select(.sessionId == $s)) | .[0].name // empty' 2>/dev/null)
# 2. pid — same session, if the registry row predates sessionId for some reason.
[ -n "$name" ] || name=$(printf '%s' "$agents" | jq -r --arg p "$pid" 'map(select(.pid == ($p|tonumber))) | .[0].name // empty' 2>/dev/null)
# 3. the name it carried at dispatch, if some live session still answers to it.
[ -n "$name" ] && [ "$name" != "null" ] || name=$(printf '%s' "$agents" | jq -r --arg n "$at_launch" 'map(select(.name == $n)) | .[0].name // empty' 2>/dev/null)
# 4. the pairing key: a live session whose name starts with it and is not itself a run. Both name
#    shapes count — `<key> · <title>` after a rename, and a bare `<key>` that was never renamed.
if [ -z "$name" ] || [ "$name" = null ]; then
  name=$(printf '%s' "$agents" | jq -r --arg k "$key" \
    'map(select(((.name == $k) or (.name | startswith($k + " "))) and (.name | contains(" · impl ") | not))) | .[0].name // empty' 2>/dev/null)
fi

[ -n "$name" ] && [ "$name" != null ] || {
  echo "cockpit gone: no live session matches sessionId=$sid pid=$pid key=$key (dispatched as '$at_launch')" >&2
  exit 1
}
printf '%s\n' "$name"
