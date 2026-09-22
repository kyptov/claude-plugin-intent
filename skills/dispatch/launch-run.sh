#!/bin/bash
# Create a plan's worktree and start its unattended Remote Control run in one uninterrupted sequence.
#
#   launch-run.sh <plan-path> --model <m> --effort <e> [--trunk <branch>] [--tag <xx>]
#                 [--install "<cmd>"] [--sync "<cmd taking the worktree path>"] [--parent "<cockpit name>"]
#   launch-run.sh --resend <plan-path> [--parent <name>] [--sock <s>] [--session <s>]
#   env: WT_BRANCH_PREFIX (default wt) — the refs/heads/<prefix>/ namespace, same knob as watch-runs.sh
#
# --resend is the recovery half: it touches no worktree and creates no session, it only makes sure
# the run ALREADY LAUNCHED is holding its plan. Use it on `SENT=unconfirmed`, and on a `STALLED …
# was its plan ever sent?` line from watch-runs.sh. It is idempotent — safe to run twice.
#
# Project-agnostic: model/effort/install/sync come from the project's .claude/workflow.md via flags.
# Without --install the install is inferred from the lockfile (pnpm/yarn/npm/bun); without --sync a
# `worktree:sync` package script is run if the repo declares one.
#
# Steps, in order: worktree + branch, dependency install, the project's worktree sync, folder
# pre-trust, the per-project tmux socket, the RC session, the registration wait, the plan hand-off
# typed at the TTY (send-keys — a cross-session message can be silently held, a keystroke cannot),
# and the hand-off confirmation. Prints a machine-readable summary on the last lines:
#   WT=<path> BRANCH=<wt/slug> SOCK=<impl-proj> SESSION=<impl-proj-slug> NAME=<tag-hex · impl slug>
#   COCKPIT_PID=<pid> SENT=yes|unconfirmed
# SENT=yes is read off the run's own transcript (the plan was submitted, not merely typed), and the
# launch already retries both hand-off failures (see confirm_pane) before it answers — so SENT=yes is
# final and needs no follow-up --resend.
#
# It also drops a dispatch record at $CLAUDE_CONFIG_DIR/dispatch-runs/<munged worktree path> holding
# the cockpit's sessionId/pid/key. That, not the `cockpit: <name>` typed onto the pane, is the run's
# real return address: a session NAME is not stable (see name_cockpit below), a sessionId is.
# `cockpit-addr.sh` turns the record back into whatever the cockpit is called at report time.
# Launch exits non-zero only on a setup failure (64-71); SENT=unconfirmed still exits 0 with the
# recovery command on stderr. --resend exits 72 (no such session — the run is gone, not stuck) or
# 73 (still unconfirmed after the retry: read the pane, it is a live session doing something else).
# The cockpit still arms `SendMessage(notify_when_idle)` itself — that is a tool, not a shell step.
#
# Requires CLAUDE_CONFIG_DIR (the profile that dispatches; never inherited by the child — it is
# pinned into the tmux command) and, for the return address, either CLAUDE_PID (to read the
# cockpit's own registered name) or --parent.
#
# Written for macOS /bin/bash 3.2: no arrays under `set -u`, no mapfile.
set -uo pipefail

plan=""; model=""; effort=""; trunk=""; install_cmd=""; sync_cmd=""; parent=""; mode=launch
sock_override=""; session_override=""; tag=""; ctitle=""; cockpit_id=""
prefix=${WT_BRANCH_PREFIX:-wt}
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model=$2; shift 2 ;;
    --effort) effort=$2; shift 2 ;;
    --trunk) trunk=$2; shift 2 ;;
    --install) install_cmd=$2; shift 2 ;;
    --sync) sync_cmd=$2; shift 2 ;;
    --parent) parent=$2; shift 2 ;;
    --tag) tag=$2; shift 2 ;;
    --cockpit-title) ctitle=$2; shift 2 ;;
    --resend) mode=resend; shift ;;
    --sock) sock_override=$2; shift 2 ;;
    --session) session_override=$2; shift 2 ;;
    -*) echo "unknown flag $1" >&2; exit 64 ;;
    *) plan=$1; shift ;;
  esac
done
[ -n "$plan" ] || { echo "usage: launch-run.sh <plan-path> --model <m> --effort <e> [flags]" >&2; exit 64; }
if [ "$mode" = launch ]; then
  [ -n "$model" ] && [ -n "$effort" ] || { echo "usage: launch-run.sh <plan-path> --model <m> --effort <e> [flags]" >&2; exit 64; }
fi

profile=${CLAUDE_CONFIG_DIR:?refuse to dispatch from an unpinned session (CLAUDE_CONFIG_DIR unset) — an unpinned run lands in ~/.claude, the profile that dispatches nothing}

# Main checkout from the COMMON git dir, so this gives the same answer from inside a worktree.
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git repo" >&2; exit 65; }
repo=$(dirname "$common")
proj=$(basename "$repo")
sock="impl-$proj"
[ -n "$trunk" ] || trunk=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -n "$trunk" ] || trunk=main

[ -f "$repo/$plan" ] || [ -f "$plan" ] || { echo "plan not found: $plan" >&2; exit 66; }
case "$plan" in /*) plan_rel=${plan#"$repo"/} ;; *) plan_rel=$plan ;; esac
slug=$(basename "$plan_rel" .md | sed -E 's/-plan$//')
branch="$prefix/$slug"
wt="$(dirname "$repo")/$proj-wt-$slug"
session="impl-$proj-$slug"
[ -z "$sock_override" ] || sock=$sock_override
[ -z "$session_override" ] || session=$session_override

# --- session naming ------------------------------------------------------------------------------
# A session list TRUNCATES the end of a name, so the one thing that must live at the FRONT is the
# pairing key: `<tag>-<hex>`, shared verbatim by a cockpit and every run it dispatches. Everything
# after it is for humans, because the operator may run several cockpits at once and "which feature is this"
# has to be readable at a glance:
#
#   sh-de · Checkout totals        <- cockpit
#   sh-de · impl cart-rounding     <- its run
#   ba-6a · Usage metering         <- another project's cockpit
#   ba-6a · impl zero-usage        <- its run
#
# So the KEY is the tag, not the cockpit's name — `--mine` filters on it, and two sessions pair iff
# their names start with the same `<tag>-<hex> `. Renaming the human half never orphans a run.
#
# `<tag>` is the project's own abbreviation, declared per project (`--tag`, from the workflow
# declaration) because no rule derives every abbreviation a project wants; the fallback is the
# initials of a hyphenated name (`billing-api -> ba`), else the first two letters (`shop -> sh`).
# `<hex>` is reused from the harness's own derived name (`shop-de` -> `de`), already unique among live sessions, so nothing new has to
# be generated or coordinated.
derive_tag() {
  [ -n "$tag" ] && return 0
  case "$proj" in
    (*-*) tag=$(printf '%s' "$proj" | awk -F- '{for(i=1;i<=NF;i++) printf substr($i,1,1)}') ;;
    (*) tag=$(printf '%s' "$proj" | cut -c1-2) ;;
  esac
}

# The cockpit's registered name, pid and sessionId. The NAME is for humans and for the pane line;
# the SESSION ID is the return address, because only it survives a rename (see name_cockpit).
cockpit_pid=""; cockpit_sid=""
resolve_parent() {
  if [ -z "$parent" ] && [ -n "${CLAUDE_PID:-}" ] && [ -f "$profile/sessions/$CLAUDE_PID.json" ]; then
    parent=$(jq -r '.name // empty' "$profile/sessions/$CLAUDE_PID.json" 2>/dev/null)
  fi
  [ -n "$parent" ] || { echo "cannot resolve the cockpit's name — pass --parent" >&2; exit 70; }
  # Prefer our own pid; otherwise find the session that currently answers to --parent.
  if [ -n "${CLAUDE_PID:-}" ] && [ -f "$profile/sessions/$CLAUDE_PID.json" ]; then
    cockpit_pid=$CLAUDE_PID
  else
    cockpit_pid=$(claude agents --json 2>/dev/null \
      | jq -r --arg n "$parent" 'map(select(.name == $n)) | .[0].pid // empty' 2>/dev/null)
  fi
  [ -n "$cockpit_pid" ] && [ -f "$profile/sessions/$cockpit_pid.json" ] \
    && cockpit_sid=$(jq -r '.sessionId // empty' "$profile/sessions/$cockpit_pid.json" 2>/dev/null)
  [ -n "$cockpit_sid" ] || echo "WARN: could not read the cockpit's sessionId — the run falls back to the name '$parent', which a re-title can break" >&2
}

# Record the cockpit's identity where the run can read it, keyed by the worktree it will live in.
# Outside the repo on purpose: an untracked file under the worktree's .claude/ is one `git add -A`
# away from landing on the trunk. Prune records whose worktree /land has already removed.
write_dispatch_record() {
  dir="$profile/dispatch-runs"
  mkdir -p "$dir" || return 0
  # Prune by the path the record itself carries — a munged name cannot be un-munged, because a
  # worktree directory legitimately contains '-' (`<proj>-wt-<slug>`).
  for old in "$dir"/*; do
    [ -f "$old" ] || continue
    gone=$(sed -n 's/^worktree=//p' "$old" 2>/dev/null)
    [ -n "$gone" ] && [ ! -d "$gone" ] && rm -f "$old" 2>/dev/null
  done
  rp=$(cd "$wt" && pwd -P)
  {
    echo "worktree=$rp"
    echo "pid=$cockpit_pid"
    echo "session_id=$cockpit_sid"
    echo "key=$cockpit_id"
    echo "name_at_launch=$parent"
  } > "$dir/$(printf '%s' "$rp" | tr '/' '-')"
}

# Rename the COCKPIT to `<tag>-<hex> · <human title>` and mark the name explicit — a session whose
# name is merely `derived` is displayed by its auto-generated title instead. The human half comes from
# --cockpit-title, else the plan's own `# ` heading, which the template requires to be the capability
# in plain words.
#
# THIS RENAME IS COSMETIC AND BEST-EFFORT. Nothing may depend on it holding. It is a write into the
# registry FILE, and the live cockpit process never reads that file back — it keeps its own name
# state — so Claude Code's conversation auto-titler overwrites it within seconds, silently. The
# `nameSource = derived` guard below cannot prevent that: it reads the state BEFORE the titler runs,
# and a cockpit that dispatches before it has ever been auto-titled is the normal case.
# The run's own name is safe because it is born explicit (`claude -n`), which the titler skips.
# The durable return address is write_dispatch_record + cockpit-addr.sh, not this name.
#
# Two refusals, both about not moving the pairing key out from under something already using it:
# never touch a name the operator set explicitly (nameSource != derived), and never rename while
# this cockpit has LIVE runs, which `watch-runs.sh --mine <key>` pairs by that key.
#
# The pairing key, read off whatever the cockpit is currently called: the leading `<tag>-<hex>` of an
# already-named cockpit, else one built from the derived name's hex. Both paths need this; only the
# launch path is allowed to rename.
derive_cockpit_id() {
  cockpit_id=$(printf '%s' "$parent" | sed -n 's/^\([a-z0-9][a-z0-9]*-[0-9a-f][0-9a-f]*\)\( .*\)*$/\1/p')
  hex=$(printf '%s' "$parent" | sed -n 's/.*-\([0-9a-f]\{2,\}\)$/\1/p')
  sf="$profile/sessions/${CLAUDE_PID:-0}.json"
  [ -n "$hex" ] || hex=$(jq -r '.sessionId' "$sf" 2>/dev/null | tr -d - | cut -c1-2)
  [ -n "$cockpit_id" ] || cockpit_id="$tag-$hex"
  [ -n "$cockpit_id" ] || cockpit_id=$parent
}

name_cockpit() {
  derive_cockpit_id
  [ -f "$sf" ] || return 0
  src=$(jq -r '.nameSource // empty' "$sf" 2>/dev/null)
  [ "$src" = derived ] || return 0
  [ -n "$hex" ] || return 0
  [ -n "$ctitle" ] || ctitle=$(sed -n '1s/^#[[:space:]]*//p' "$repo/$plan_rel" 2>/dev/null | cut -c1-40)
  [ -n "$ctitle" ] || ctitle=$slug
  want="$tag-$hex · $ctitle"
  [ "$want" != "$parent" ] || return 0
  # Match live runs by the pairing KEY, not the cockpit's name: the cockpit may have been re-titled
  # since its last dispatch, and then its runs no longer contain its CURRENT name.
  if claude agents --json 2>/dev/null | jq -e --arg k "$cockpit_id" \
       '.[] | select(.name | startswith($k + " · impl "))' >/dev/null 2>&1; then
    echo "WARN: keeping the cockpit name '$parent' — it has live runs whose return address is that name." >&2
    echo "WARN: it will be renamed to '$want' on the first dispatch after those land." >&2
    return 0
  fi
  # Only NOW may the key move: every `return 0` above leaves `cockpit_id` as derive_cockpit_id read
  # it off the CURRENT name, so a refused rename still names this run with the key the cockpit
  # actually carries. Assigning it before the refusals would tag runs `sh-de` under a cockpit still
  # called `shop-de`.
  cockpit_id="$tag-$hex"
  python3 - "$sf" "$want" <<'PY'
import json, os, sys, tempfile
p, want = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["name"] = want
d["nameSource"] = "explicit"
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p)); os.close(fd)
with open(tmp, "w") as f: json.dump(d, f)
os.replace(tmp, p)
PY
  echo "==> cockpit renamed: $parent -> $want"
  parent=$want
}

# Did the run SUBMIT its plan? The proof is the run's own transcript, not the pane: a submitted
# `/deliver <plan>` is written there as a user turn carrying `<command-args><plan>`, and nothing else
# writes that. The pane cannot tell — a line typed but never submitted reads exactly like a sent one.
# The transcript is found through the run's own registry record (cwd == worktree), so a transcript
# left behind by an earlier run of the same slug can never vouch for this one.
plan_submitted() {
  run_rp=$(cd "$wt" 2>/dev/null && pwd -P) || return 1
  tdir="$profile/projects/$(printf '%s' "$run_rp" | sed 's#[^A-Za-z0-9]#-#g')"
  for rec in $(grep -ls "\"cwd\":\"$run_rp\"" "$profile"/sessions/*.json 2>/dev/null); do
    sid=$(jq -r '.sessionId // empty' "$rec" 2>/dev/null)
    [ -n "$sid" ] || continue
    grep -qsF "<command-args>$plan_rel" "$tdir/$sid.jsonl" && return 0
  done
  return 1
}

wait_submitted() {
  for _ in $(seq "$1"); do
    plan_submitted && return 0
    sleep 1
  done
  return 1
}

# Settle the hand-off: wait for the transcript to show the plan, and if it does not, clear the two
# ways a typed line fails to submit, then wait again. Sets $pane and $sent.
#   1. a "held message / review it below" box swallows the line — answer it with Down Enter;
#   2. the Enter itself is eaten (the idle subscription, or a box that appeared between the text and
#      the newline), leaving the command sitting UNSENT in the input box. Press Enter on its own
#      rather than retyping the line, which would queue a second /deliver.
# SENT=yes therefore means submitted, not "visible on the pane" — the cockpit acts on it as final.
confirm_pane() {
  sent=unconfirmed
  if ! wait_submitted 15; then
    pane=$(tmux -L "$sock" capture-pane -p -t "$session" 2>/dev/null)
    if printf '%s' "$pane" | grep -qi "held message\|review it below"; then
      echo "==> plan not submitted — answering a held-message box" >&2
      tmux -L "$sock" send-keys -t "$session" Down Enter
    elif printf '%s' "$pane" | tail -6 | grep -q '/deliver'; then
      echo "==> plan typed but not submitted — pressing Enter" >&2
      tmux -L "$sock" send-keys -t "$session" Enter
    fi
    wait_submitted 20 || { pane=$(tmux -L "$sock" capture-pane -p -t "$session" 2>/dev/null); return 0; }
  fi
  sent=yes
  pane=$(tmux -L "$sock" capture-pane -p -t "$session" 2>/dev/null)
  return 0
}

send_plan() {
  tmux -L "$sock" send-keys -t "$session" "/deliver $plan_rel   cockpit: $parent" Enter
  confirm_pane
}

summary() {
  echo "WT=$wt BRANCH=$branch SOCK=$sock SESSION=$session NAME=${cockpit_id} · impl ${slug}"
  echo "COCKPIT_PID=${cockpit_pid:-unknown} SENT=$sent"
  [ "$sent" = yes ] || { echo "pane tail:" >&2; printf '%s\n' "$pane" | tail -15 >&2; }
}

# --- --resend: verify the hand-off landed, and finish it if it did not ---------------------------
if [ "$mode" = resend ]; then
  tmux -L "$sock" has-session -t "$session" 2>/dev/null || {
    echo "no tmux session '$session' on socket '$sock' — the run is gone, not stuck." >&2
    echo "Dispatch it again (the worktree may need removing first: $wt)." >&2
    exit 72
  }
  derive_tag
  resolve_parent
  derive_cockpit_id
  pane=$(tmux -L "$sock" capture-pane -p -t "$session" 2>/dev/null)
  # Match the PLAN, never "cockpit: $parent": the cockpit may have been re-titled since launch, and
  # then an exact-name test finds nothing on a pane that is in fact holding its plan — and types a
  # second /deliver line onto a working run.
  if plan_submitted; then
    echo "==> the run's transcript already holds its plan — nothing to resend"
    sent=yes
  elif printf '%s' "$pane" | grep -qF "/deliver $plan_rel"; then
    # The line is on screen — which does not mean it was submitted. Let confirm_pane settle it
    # rather than typing a second copy.
    echo "==> plan line already on the pane — confirming it was submitted, not just typed"
    confirm_pane
  else
    echo "==> no plan line on the pane — sending it"
    send_plan
  fi
  summary
  [ "$sent" = yes ] || exit 73
  exit 0
fi

if [ -e "$wt" ] || git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "worktree or branch already exists: $wt / $branch — land or remove it first" >&2; exit 67
fi

echo "==> worktree $wt on $branch from $trunk"
git -C "$repo" worktree add "$wt" -b "$branch" "$trunk" || exit 68

if [ -z "$install_cmd" ]; then
  if [ -f "$repo/pnpm-lock.yaml" ]; then install_cmd="pnpm install"
  elif [ -f "$repo/yarn.lock" ]; then install_cmd="yarn install --frozen-lockfile"
  elif [ -f "$repo/bun.lockb" ] || [ -f "$repo/bun.lock" ]; then install_cmd="bun install"
  elif [ -f "$repo/package-lock.json" ]; then install_cmd="npm ci"
  fi
fi
if [ -n "$install_cmd" ]; then
  echo "==> install: $install_cmd"
  (cd "$wt" && eval "$install_cmd") || { echo "install failed" >&2; exit 69; }
fi

# The project's own worktree sync (copies gitignored local config/env per its allow-list), run from
# the MAIN checkout. Default: a `worktree:sync` package script when the repo declares one.
if [ -z "$sync_cmd" ] && [ -f "$repo/package.json" ] && jq -e '.scripts["worktree:sync"]' "$repo/package.json" >/dev/null 2>&1; then
  case "$install_cmd" in yarn*) sync_cmd="yarn worktree:sync" ;; bun*) sync_cmd="bun run worktree:sync" ;; npm*) sync_cmd="npm run worktree:sync --" ;; *) sync_cmd="pnpm worktree:sync" ;; esac
fi
if [ -n "$sync_cmd" ]; then
  echo "==> sync: $sync_cmd $wt"
  (cd "$repo" && eval "$sync_cmd \"$wt\"") || echo "WARN: worktree sync failed — the run may lack local env / settings files" >&2
fi

# Pre-trust the folder: read–modify–atomic-replace, because live sessions rewrite .claude.json too.
python3 - "$profile" "$wt" <<'PY'
import json, os, sys, tempfile
cfg = os.path.join(sys.argv[1], ".claude.json")
d = json.load(open(cfg)) if os.path.exists(cfg) else {}
d.setdefault("projects", {}).setdefault(os.path.realpath(sys.argv[2]), {})["hasTrustDialogAccepted"] = True
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg)); os.close(fd)
with open(tmp, "w") as f: json.dump(d, f)
os.replace(tmp, cfg)
PY

derive_tag
resolve_parent
name_cockpit
write_dispatch_record
name="${cockpit_id} · impl ${slug}"

echo "==> tmux -L $sock: $session"
# CLAUDE_CODE_PROMPT_CACHE_TTL=5m: a dispatched run's turns are back to back (p99 gap ~140s), so the
# 5-minute entry is refreshed by the next turn and the 1-hour TTL's 2x write premium (vs 1.25x) buys
# nothing. The COCKPIT is the opposite case and stays on 1h: it waits on a watcher for many minutes
# at a time. Do not make a gate block in the FOREGROUND for >5 minutes — that creates exactly the
# gaps this setting bets against.
tmux -L "$sock" new-session -d -s "$session" -c "$wt" \
  "env CLAUDE_CONFIG_DIR=$profile CLAUDE_CODE_PROMPT_CACHE_TTL=5m CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=5m claude --remote-control -n '$name' --model $model --effort $effort --permission-mode bypassPermissions" \
  || { echo "tmux launch failed" >&2; exit 71; }

# Wait for the session to register under its RESOLVED cwd (a symlinked root registers its real path).
rp=$(cd "$wt" && pwd -P)
registered=0
for _ in $(seq 40); do
  if grep -ls "\"cwd\":\"$rp\"" "$profile"/sessions/*.json >/dev/null 2>&1; then registered=1; break; fi
  sleep 2
done
[ "$registered" = 1 ] || echo "WARN: session did not register within 80s — sending anyway" >&2
sleep 3

# Hand over the plan by typing at the TTY. One line: the plan, then the return address.
send_plan

summary
[ "$sent" = yes ] || echo "recover with: launch-run.sh --resend $plan_rel --parent \"$parent\"" >&2
exit 0
