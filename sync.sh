#!/bin/bash
# Single source of truth for the workflow skills: ~/.claude-skills/workflow/
# Copies them into every Claude profile that exists on this machine, so `/intent` behaves
# identically whichever profile a session starts under.
#
# Project-specific facts do NOT live here — each repo carries .claude/workflow.md.
# Run after editing anything under workflow/.
#
# REFUSES TO SYNC OVER NEWER WORK unless --force. Measured 2026-09-18: workflow/ had been left a
# month behind while all three profile copies were edited in place, so running this would have
# silently REVERTED every profile to the August tree — a destructive no-warning downgrade from a
# script whose whole job is "make them identical". Edit workflow/, not a profile copy; if you did
# edit a profile copy, copy it back into workflow/ first.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/workflow"
force=0
[ "${1:-}" = "--force" ] && force=1

if [ "$force" = 0 ]; then
  stale=0
  for prof in "$HOME"/.claude "$HOME"/.claude-work "$HOME"/.claude-personal; do
    [ -d "$prof/skills" ] || continue
    for s in intent dispatch deliver land; do
      [ -d "$prof/skills/$s" ] || continue
      diff -rq "$SRC/$s" "$prof/skills/$s" >/dev/null 2>&1 && continue
      # differs — is the profile copy the NEWER one?
      newest_src=$(find "$SRC/$s" -type f -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)
      newest_prof=$(find "$prof/skills/$s" -type f -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)
      if [ "${newest_prof:-0}" -gt "${newest_src:-0}" ]; then
        echo "REFUSING: $prof/skills/$s is NEWER than the source and differs from it." >&2
        diff -rq "$SRC/$s" "$prof/skills/$s" >&2 || true
        stale=1
      fi
    done
  done
  [ "$stale" = 0 ] || {
    echo >&2
    echo "Copy the newer tree into $SRC first, or re-run with --force to overwrite it." >&2
    exit 1
  }
fi

for prof in "$HOME"/.claude "$HOME"/.claude-work "$HOME"/.claude-personal; do
  [ -d "$prof" ] || continue
  mkdir -p "$prof/skills"
  for s in intent dispatch deliver land; do
    rm -rf "$prof/skills/$s"
    cp -R "$SRC/$s" "$prof/skills/$s"
  done
  echo "synced -> $prof/skills"
done
