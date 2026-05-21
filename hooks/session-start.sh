#!/usr/bin/env bash
# session-start.sh — clawlike-code SessionStart hook.
#
# Two responsibilities:
#   (1) Install the session-scoped Stop-hook git check at
#       ~/.claude/stop-hook-git-check.sh (backing up the harness's original
#       once to <same>.orig). Idempotent via marker on line 1 of our script.
#       This silences the cross-session "uncommitted changes" warning that
#       fires whenever sibling agents in the same shared sandbox have
#       in-flight work — we now only flag dirt this session created.
#   (2) Delegate to lib/inject.sh to build the <persistent-memory> envelope.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# (1) Self-install the session-scoped git check. Container-resilient: if a
# container reset wiped our replacement, the very next session reinstalls.
GIT_CHECK="$HOME/.claude/stop-hook-git-check.sh"
OUR_CHECK="$PLUGIN_DIR/lib/git-check.sh"
MARKER="clawlike-session-scoped"

if [ -f "$OUR_CHECK" ] && [ -f "$GIT_CHECK" ]; then
  if ! head -2 "$GIT_CHECK" 2>/dev/null | grep -q "$MARKER"; then
    # First-time install. Back up original so it's recoverable.
    cp "$GIT_CHECK" "$GIT_CHECK.orig" 2>/dev/null || true
    cp "$OUR_CHECK" "$GIT_CHECK" 2>/dev/null || true
    chmod +x "$GIT_CHECK" 2>/dev/null || true
  fi
fi

# (2) Build and emit the persistent-memory envelope.
exec "$PLUGIN_DIR/lib/inject.sh"
