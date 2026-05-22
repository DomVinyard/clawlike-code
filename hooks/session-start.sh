#!/usr/bin/env bash
# session-start.sh — clawlike-code SessionStart hook.
#
# Responsibilities:
#   (1) Install (or upgrade) the session-scoped Stop-hook git check at
#       ~/.claude/stop-hook-git-check.sh, backing up the harness's original
#       to <same>.orig the first time it lands. Version-tagged via the
#       `clawlike-session-scoped v<N>` marker on line 2; the install code
#       compares the installed version against the plugin's shipped
#       version and overwrites on mismatch. Container-resilient: if a
#       container reset wipes our replacement, the next session reinstalls.
#       Orthogonal to the plumbing-based Stop hook (which keeps the
#       plugin's own writes out of the working tree) — this scopes the
#       check to paths the current session touched, so sibling-session
#       dirt in the shared sandbox doesn't bother us.
#   (2) Delegate to lib/inject.sh to build the <persistent-memory>
#       envelope.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# (1) Self-install / upgrade the session-scoped git check.
GIT_CHECK="$HOME/.claude/stop-hook-git-check.sh"
OUR_CHECK="$PLUGIN_DIR/lib/git-check.sh"
MARKER="clawlike-session-scoped"

if [ -f "$OUR_CHECK" ] && [ -f "$GIT_CHECK" ]; then
  installed_ver=$(head -2 "$GIT_CHECK" 2>/dev/null | grep -oE "$MARKER v[0-9]+" || true)
  source_ver=$(head -2 "$OUR_CHECK" 2>/dev/null | grep -oE "$MARKER v[0-9]+" || true)
  if [ "$installed_ver" != "$source_ver" ] && [ -n "$source_ver" ]; then
    # First-time install: back up the harness's original (no marker yet).
    if [ -z "$installed_ver" ] && [ ! -f "$GIT_CHECK.orig" ]; then
      cp "$GIT_CHECK" "$GIT_CHECK.orig" 2>/dev/null || true
    fi
    cp "$OUR_CHECK" "$GIT_CHECK" 2>/dev/null || true
    chmod +x "$GIT_CHECK" 2>/dev/null || true
  fi
fi

# (2) Build and emit the persistent-memory envelope.
exec "$PLUGIN_DIR/lib/inject.sh"
