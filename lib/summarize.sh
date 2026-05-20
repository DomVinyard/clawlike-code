#!/usr/bin/env bash
# summarize.sh — on final stop (stop_hook_active=true), prepend a one-paragraph
# Haiku summary to the session file at .clawlike/sessions/<id>.md.
#
# Idempotent: if a "## Summary" block already exists at the top, skip.
# Auth: same as classify.sh — Claude Code's session ingress token, available
# at $CLAUDE_SESSION_INGRESS_TOKEN_FILE in every hook subprocess.
#
# Env vars:
#   CLAWLIKE_SESSION_FILE — if set, read and write THIS file in place instead
#                           of the default $SESSIONS_DIR/<session-id>.md. Used
#                           by stop.sh to route through staging.
#
# Always exits 0 — best-effort.

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSIONS_DIR="$REPO_ROOT/.clawlike/sessions"
MODEL="${CLAWLIKE_MODEL:-claude-haiku-4-5-20251001}"
API_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}/v1/messages"

HOOK_JSON=$(cat 2>/dev/null || true)
[ -n "$HOOK_JSON" ] || exit 0

STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] || exit 0

SESSION_ID=$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

SESSION_FILE="${CLAWLIKE_SESSION_FILE:-$SESSIONS_DIR/${SESSION_ID}.md}"
[ -f "$SESSION_FILE" ] || exit 0

if head -3 "$SESSION_FILE" | grep -q '^## Summary'; then
  exit 0
fi

TOKEN_FILE="${CLAUDE_SESSION_INGRESS_TOKEN_FILE:-}"
[ -n "$TOKEN_FILE" ] && [ -f "$TOKEN_FILE" ] || exit 0
SESSION_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null | tr -d '\n')
[ -n "$SESSION_TOKEN" ] || exit 0

TMP_PROMPT=$(mktemp)
TMP_RESP=$(mktemp)
trap 'rm -f "$TMP_PROMPT" "$TMP_RESP"' EXIT

{
  echo "Summarise the following session transcript in ONE paragraph (3-4 sentences max). Lead with what was accomplished or decided. Mention any unresolved items at the end. Output ONLY the paragraph — no preamble, no headers, no quotes."
  echo "---"
  head -c 80000 "$SESSION_FILE"
} >"$TMP_PROMPT"

REQUEST_BODY=$(jq -n \
  --arg model "$MODEL" \
  --rawfile prompt "$TMP_PROMPT" \
  '{model:$model, max_tokens:300, messages:[{role:"user", content:$prompt}]}')

HTTP_CODE=$(curl -s -o "$TMP_RESP" -w "%{http_code}" \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --max-time 30 \
  --data-binary @<(printf '%s' "$REQUEST_BODY") \
  "$API_URL")

[ "$HTTP_CODE" = "200" ] || exit 0

SUMMARY=$(jq -r '.content[0].text // empty' "$TMP_RESP" 2>/dev/null)
[ -n "$SUMMARY" ] || exit 0

SUMMARY=$(printf '%s\n' "$SUMMARY" | sed -E 's/^#+ Summary//' | sed -E 's/^[[:space:]]+//')

TMP_OUT=$(mktemp)
{
  echo "## Summary"
  echo
  printf '%s\n' "$SUMMARY"
  echo
  cat "$SESSION_FILE"
} >"$TMP_OUT"
mv "$TMP_OUT" "$SESSION_FILE"

exit 0
