#!/usr/bin/env bash
# stop.sh — clawlike-code Stop hook.
#
# Responsibilities:
#   (a) Transcribe — append/update the session transcript
#   (b) Summarize — on final stop, prepend a one-paragraph Haiku summary
#   (c) Classify — on first stop, run the Haiku safety-net classifier and
#       (if it proposes something) prepare an append to MEMORY.md
#   (d) Commit — atomically commit and push (a/b/c)'s writes
#
# Race-free design: (a), (b), (c) route ALL writes through a staging
# directory under $XDG_CACHE_HOME/clawlike-code/staging/ — the working
# tree is never dirty while the plugin is running. The (d) step uses git
# plumbing (hash-object → write-tree → commit-tree → update-ref → restore)
# to land everything in HEAD before touching the working tree. This makes
# the plugin invisible to harness-level "no uncommitted changes" checks
# (e.g. Claude Code Cloud's stop-hook-git-check.sh).
#
# Always exits 0 unless decision:block is returned by the classifier.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

HOOK_JSON=$(cat 2>/dev/null || true)
[ -n "$HOOK_JSON" ] || exit 0

SESSION_ID=$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

# Staging area lives outside the consumer repo. One subdirectory per
# session ID so concurrent sessions don't trample each other.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/clawlike-code"
STAGING_DIR="$CACHE_DIR/staging/$SESSION_ID"
mkdir -p "$STAGING_DIR" 2>/dev/null || true

SESSION_STAGED="$STAGING_DIR/session.md"
MEMORY_STAGED="$STAGING_DIR/MEMORY.md"

# Seed the staging session file from the working tree if it exists, so
# transcribe.sh's "preserve existing ## Summary block" logic still works
# across turns.
SESSION_LIVE="$REPO_ROOT/.clawlike/sessions/${SESSION_ID}.md"
if [ -f "$SESSION_LIVE" ] && [ ! -f "$SESSION_STAGED" ]; then
  cp "$SESSION_LIVE" "$SESSION_STAGED" 2>/dev/null || true
fi

MEMORY_LIVE="$REPO_ROOT/.clawlike/context/MEMORY.md"

# (a) Transcribe — always. Output goes to staging.
printf '%s' "$HOOK_JSON" | \
  CLAWLIKE_OUT_PATH="$SESSION_STAGED" "$PLUGIN_DIR/lib/transcribe.sh" || true

STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # (b) Final stop — summarize the staged session file.
  printf '%s' "$HOOK_JSON" | \
    CLAWLIKE_SESSION_FILE="$SESSION_STAGED" "$PLUGIN_DIR/lib/summarize.sh" \
    2>/dev/null || true

  "$PLUGIN_DIR/lib/commit.sh" "$SESSION_ID" "$SESSION_STAGED" "" >/dev/null 2>&1 || true
  exit 0
fi

# (c) First stop — run the classifier. Reads MEMORY.md from working tree
# (current committed state), writes the proposed new content (with the
# pending entry appended) to staging.
CLASSIFY_OUTPUT=$(printf '%s' "$HOOK_JSON" | \
  CLAWLIKE_MEMORY_IN="$MEMORY_LIVE" \
  CLAWLIKE_MEMORY_OUT="$MEMORY_STAGED" \
  "$PLUGIN_DIR/lib/classify.sh" 2>/dev/null || true)

# (d) Commit and push everything in staging. If MEMORY_STAGED doesn't
# exist (no classifier proposal this turn), commit.sh skips it.
MEMORY_ARG=""
[ -f "$MEMORY_STAGED" ] && MEMORY_ARG="$MEMORY_STAGED"
"$PLUGIN_DIR/lib/commit.sh" "$SESSION_ID" "$SESSION_STAGED" "$MEMORY_ARG" >/dev/null 2>&1 || true

if [ -n "$CLASSIFY_OUTPUT" ]; then
  printf '%s' "$CLASSIFY_OUTPUT"
fi

exit 0
