#!/usr/bin/env bash
# stop.sh — clawlike-code Stop hook.
#
# Responsibilities:
#   (a) Transcribe — always append/update .clawlike/sessions/<session-id>.md
#   (b) Summarize — on final stop (stop_hook_active=true), prepend a one-paragraph Haiku summary
#   (c) Classify — on first stop (stop_hook_active=false), run a Haiku safety-net classifier
#       and propose memory edits via:
#         - Appending to MEMORY.md "## Pending Lessons"
#         - Returning decision:block + reason (so the agent addresses it in-turn)
#
# Always exits 0 unless decision:block is returned.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"


# Read the hook payload from stdin once; both transcribe and classify need it.
HOOK_JSON=$(cat 2>/dev/null || true)

# (a) Transcribe — best-effort, always.
printf '%s' "$HOOK_JSON" | "$PLUGIN_DIR/lib/transcribe.sh" || true

# Decide whether to summarize and/or classify based on stop_hook_active.
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Final stop after a previous block — write summary, don't re-classify.
  printf '%s' "$HOOK_JSON" | "$PLUGIN_DIR/lib/summarize.sh" 2>/dev/null || true
  exit 0
fi

# First stop on this turn — run the classifier (it handles cooldown internally).
# classify.sh emits hookSpecificOutput JSON on stdout if a proposal exists,
# otherwise stays silent.
CLASSIFY_OUTPUT=$(printf '%s' "$HOOK_JSON" | "$PLUGIN_DIR/lib/classify.sh" 2>/dev/null || true)

if [ -n "$CLASSIFY_OUTPUT" ]; then
  printf '%s' "$CLASSIFY_OUTPUT"
fi

exit 0
