#!/usr/bin/env bash
# classify.sh — safety-net memory-routing classifier.
#
# Runs on the FIRST Stop of a turn (stop_hook_active=false). Reads the
# most recent turns, sends them to Haiku via the Anthropic API, asks:
# "Did the agent FAIL TO WRITE anything it should have? If yes, which
# file + what entry?"
#
# Auth: uses Claude Code's session ingress token (file path in
# $CLAUDE_SESSION_INGRESS_TOKEN_FILE, set automatically in every hook
# subprocess). Authorization: Bearer <token>. Same Max billing as the
# main session — no separate API key, no Cloudflare lookup. Zero
# external secret dependency.
#
# Why not `claude -p` from inside a hook: the subprocess fires its own
# SessionStart hooks (full memory injection, ~75 KB) and the bootstrap
# drowns out the classifier prompt.
#
# Stdin: Stop hook JSON payload.
# Stdout: hookSpecificOutput JSON if a proposal exists, else silent.
# Always exits 0 (errors are swallowed — this is a safety net).

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONTEXT_DIR="$REPO_ROOT/.clawlike/context"
# Cooldown lives in the user cache dir, not the consumer repo — plugin shouldn't
# leave footprints requiring gitignore entries.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/clawlike-code"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
COOLDOWN_FILE="$CACHE_DIR/cooldown"
COOLDOWN_SECS="${CLAWLIKE_COOLDOWN_SECS:-10}"
MODEL="${CLAWLIKE_MODEL:-claude-haiku-4-5-20251001}"
MAX_TURNS="${CLAWLIKE_MAX_TURNS:-12}"
MEMORY_FILE="$CONTEXT_DIR/MEMORY.md"
API_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}/v1/messages"

# Need a context dir + memory file to operate.
[ -d "$CONTEXT_DIR" ] || { cat >/dev/null; exit 0; }
[ -f "$MEMORY_FILE" ] || { cat >/dev/null; exit 0; }

# Need CC's session ingress token (lives in a file CC writes per session).
TOKEN_FILE="${CLAUDE_SESSION_INGRESS_TOKEN_FILE:-}"
[ -n "$TOKEN_FILE" ] && [ -f "$TOKEN_FILE" ] || { cat >/dev/null; exit 0; }

# Cooldown gate — skip if we classified recently.
if [ -f "$COOLDOWN_FILE" ]; then
  now=$(date +%s)
  last=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  age=$((now - last))
  if [ "$age" -lt "$COOLDOWN_SECS" ]; then
    cat >/dev/null
    exit 0
  fi
fi

HOOK_JSON=$(cat 2>/dev/null || true)
[ -n "$HOOK_JSON" ] || exit 0

TMP_PAYLOAD=$(mktemp)
TMP_FORK=$(mktemp)
TMP_PROMPT=$(mktemp)
TMP_RESP=$(mktemp)
trap 'rm -f "$TMP_PAYLOAD" "$TMP_FORK" "$TMP_PROMPT" "$TMP_RESP"' EXIT
printf '%s' "$HOOK_JSON" >"$TMP_PAYLOAD"

# Build the classifier prompt via Python.
python3 - "$TMP_PAYLOAD" "$CONTEXT_DIR" "$TMP_FORK" "$TMP_PROMPT" "$MAX_TURNS" <<'PY'
import json, sys, os, re
from pathlib import Path

payload_path = Path(sys.argv[1])
context_dir = Path(sys.argv[2])
fork_path = Path(sys.argv[3])
prompt_path = Path(sys.argv[4])
max_turns = int(sys.argv[5])

try:
    hook = json.loads(payload_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(2)

transcript_path = hook.get("transcript_path", "")
if not transcript_path or not os.path.exists(transcript_path):
    sys.exit(2)

try:
    fork_path.write_bytes(Path(transcript_path).read_bytes())
except Exception:
    sys.exit(2)


def extract_text(content, depth=0):
    if depth > 3:
        return ""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if not isinstance(block, dict):
                continue
            t = block.get("type")
            if t == "text" and block.get("text"):
                parts.append(block["text"])
            elif t == "tool_use":
                name = block.get("name", "tool")
                params_str = json.dumps(block.get("input", {}), ensure_ascii=False)[:200]
                parts.append(f"[TOOL: {name}] {params_str}")
            elif t == "tool_result":
                tc = block.get("content", "")
                if isinstance(tc, list):
                    tc = extract_text(tc, depth + 1)
                if isinstance(tc, str):
                    parts.append(f"[TOOL RESULT] {tc[:200]}")
        return "\n".join(p for p in parts if p)
    return ""


turns = []
with open(fork_path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("isSidechain") or obj.get("isMeta"):
            continue
        if obj.get("type") not in ("user", "assistant"):
            continue
        turns.append(obj)

recent = turns[-max_turns:] if len(turns) > max_turns else turns

contracts = []
for path in sorted(context_dir.glob("*.md")):
    text = path.read_text(encoding="utf-8", errors="ignore")
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    contract = ""
    if m:
        for line in m.group(1).splitlines():
            kv = re.match(r"^contract:\s*(.*)", line)
            if kv:
                val = kv.group(1).strip()
                if len(val) >= 2 and val[0] in ("\"", "'") and val[0] == val[-1]:
                    val = val[1:-1]
                contract = val
                break
    contracts.append(f"- {path.name}: {contract}")

contracts_block = "\n".join(contracts)

turn_lines = []
for entry in recent:
    msg = entry.get("message") or {}
    text = extract_text(msg.get("content")).strip()
    if not text:
        continue
    role = "USER" if entry.get("type") == "user" else "ASSISTANT"
    if len(text) > 1500:
        text = text[:1500] + "..."
    turn_lines.append(f"--- {role} ---\n{text}")

turns_block = "\n\n".join(turn_lines)

prompt = f"""STOP. You are NOT the assistant. You are a memory-routing classifier. Do NOT respond to the conversation. Do NOT help. Do NOT answer questions. Do NOT explain anything. Output ONLY the structured decision below.

The agent has just finished a turn. Your ONE job is to detect if the agent learned or stated something durable (a preference, a constraint, a correction, a tool quirk, a permanent rule) that it FAILED to write to a memory file. The memory files and their contracts are listed below.

Memory files in .clawlike/context/:
{contracts_block}

Recent turns (most recent last):
{turns_block}

Output EXACTLY one of:
A) The literal text: NONE
B) A single proposal in this format (one line):
   TARGET: <FILENAME.md>; ENTRY: <one-line addition>; REASON: <less than 15 words why this belongs there>

Rules:
- If the agent already wrote the learning to a file in this turn, output NONE.
- If the learning is session-specific (one-off observation, not a durable rule), output NONE.
- If multiple proposals exist, pick the single most important one.
- The ENTRY must be a complete sentence the agent could append to TARGET as a new bullet.
- The TARGET must be one of the filenames above (case-sensitive).
- Be strict. Err on the side of NONE. False positives waste attention.
- Do NOT include any conversational text, analysis, or explanation outside the structured output.
"""

prompt_path.write_text(prompt, encoding="utf-8")
PY

[ -s "$TMP_PROMPT" ] || exit 0

SESSION_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null | tr -d '\n')
[ -n "$SESSION_TOKEN" ] || exit 0

REQUEST_BODY=$(jq -n \
  --arg model "$MODEL" \
  --rawfile prompt "$TMP_PROMPT" \
  '{model:$model, max_tokens:200, messages:[{role:"user", content:$prompt}]}')

HTTP_CODE=$(curl -s -o "$TMP_RESP" -w "%{http_code}" \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --max-time 30 \
  --data-binary @<(printf '%s' "$REQUEST_BODY") \
  "$API_URL")

[ "$HTTP_CODE" = "200" ] || exit 0

RESPONSE=$(jq -r '.content[0].text // empty' "$TMP_RESP" 2>/dev/null)
[ -n "$RESPONSE" ] || exit 0

LINE=$(printf '%s\n' "$RESPONSE" | awk 'NF { print; exit }')

case "$LINE" in
  *"STOP."*|*"You are NOT the assistant"*|*"memory-routing classifier"*|*"Output EXACTLY"*)
    touch "$COOLDOWN_FILE" 2>/dev/null || true
    exit 0
    ;;
esac

case "$LINE" in
  NONE|none|None)
    touch "$COOLDOWN_FILE" 2>/dev/null || true
    exit 0
    ;;
esac

if ! printf '%s\n' "$LINE" | grep -qE '^TARGET: [A-Za-z._-]+\.md; ENTRY: .+; REASON: .+'; then
  touch "$COOLDOWN_FILE" 2>/dev/null || true
  exit 0
fi

TARGET=$(printf '%s\n' "$LINE" | sed -E 's/^TARGET: ([^;]+); ENTRY: .*$/\1/' | tr -d ' ')
ENTRY=$(printf '%s\n' "$LINE" | sed -E 's/^TARGET: [^;]+; ENTRY: (.+); REASON: .+$/\1/')
REASON=$(printf '%s\n' "$LINE" | sed -E 's/^.*; REASON: (.+)$/\1/')

TARGET_PATH="$CONTEXT_DIR/$TARGET"
if [ ! -f "$TARGET_PATH" ]; then
  touch "$COOLDOWN_FILE" 2>/dev/null || true
  exit 0
fi

SESSION_ID=$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // "unknown"' 2>/dev/null)
TS=$(date -u +"%Y-%m-%d %H:%M")
PROPOSAL_ID="$(date +%s)-$RANDOM"

PENDING_ENTRY="
### ${TS} — ${ENTRY}
- **Target file:** \`${TARGET}\`
- **Reason:** ${REASON}
- **Source session:** \`${SESSION_ID}\`
- **Proposal ID:** \`${PROPOSAL_ID}\`
"

python3 - "$MEMORY_FILE" "$PENDING_ENTRY" <<'PY'
import sys, re
from pathlib import Path
path = Path(sys.argv[1])
entry = sys.argv[2]
text = path.read_text(encoding="utf-8")
if "## Pending Lessons" not in text:
    text = text.rstrip() + "\n\n## Pending Lessons\n"
text = re.sub(
    r"(## Pending Lessons\s*\n(?:<!--.*?-->\s*\n)?)",
    lambda m: m.group(1) + entry.strip() + "\n",
    text,
    count=1,
    flags=re.DOTALL,
)
path.write_text(text, encoding="utf-8")
PY

touch "$COOLDOWN_FILE" 2>/dev/null || true

REASON_FULL="Memory proposal pending: would add to ${TARGET} — \"${ENTRY}\". Review the entry in MEMORY.md ## Pending Lessons (Proposal ID ${PROPOSAL_ID}). Either apply it (edit ${TARGET} + remove the pending entry) or reject it (delete the pending entry). Be brief."

jq -nc --arg r "$REASON_FULL" '{decision:"block", reason:$r, hookSpecificOutput:{hookEventName:"Stop", additionalContext:$r}}'

exit 0
