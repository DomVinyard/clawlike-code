#!/usr/bin/env bash
# transcribe.sh — copies/syncs the Claude Code session JSONL into
# .clawlike/sessions/<session-id>.md as a readable markdown transcript.
#
# Stdin: the Stop hook's JSON payload (session_id, transcript_path, etc).
# Always exits 0 — best-effort.
#
# Env vars:
#   CLAWLIKE_OUT_PATH — if set, write to this exact file instead of
#                       $SESSIONS_DIR/<session-id>.md. Used by stop.sh to
#                       route writes through staging so the working tree
#                       stays clean during plugin runs (race-free vs the
#                       harness Stop-hook git check).

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSIONS_DIR="$REPO_ROOT/.clawlike/sessions"
OUT_PATH="${CLAWLIKE_OUT_PATH:-}"

# Only create the default sessions dir if we're writing there.
[ -z "$OUT_PATH" ] && mkdir -p "$SESSIONS_DIR"

HOOK_JSON=$(cat 2>/dev/null || true)
if [ -z "$HOOK_JSON" ]; then
  exit 0
fi

# Stash the payload in a temp file so Python can read it cleanly without
# bash-escaping pitfalls.
TMP_PAYLOAD=$(mktemp)
trap 'rm -f "$TMP_PAYLOAD"' EXIT
printf '%s' "$HOOK_JSON" >"$TMP_PAYLOAD"

python3 - "$SESSIONS_DIR" "$TMP_PAYLOAD" "$OUT_PATH" <<'PY'
import json, sys, os, re
from pathlib import Path
from datetime import datetime, timezone

sessions_dir = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
out_override = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ""

try:
    hook = json.loads(payload_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

session_id = hook.get("session_id") or ""
transcript_path = hook.get("transcript_path") or ""
if not session_id or not transcript_path or not os.path.exists(transcript_path):
    sys.exit(0)

turns = []
try:
    with open(transcript_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                turns.append(json.loads(line))
            except Exception:
                continue
except Exception:
    sys.exit(0)


def extract_text(content):
    """Pull human-readable text out of a message.content payload."""
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
                params = block.get("input", {})
                params_str = json.dumps(params, ensure_ascii=False)
                if len(params_str) > 400:
                    params_str = params_str[:400] + "..."
                parts.append(f"[TOOL: {name}] {params_str}")
            elif t == "tool_result":
                tc = block.get("content", "")
                if isinstance(tc, list):
                    tc = extract_text(tc)
                if isinstance(tc, str) and len(tc) > 400:
                    tc = tc[:400] + "..."
                parts.append(f"[TOOL RESULT] {tc}")
        return "\n\n".join(p for p in parts if p)
    return ""


lines = []
lines.append(f"# Session {session_id}")
lines.append("")
lines.append(f"<!-- transcript_path: {transcript_path} -->")
lines.append(f"<!-- written: {datetime.now(timezone.utc).isoformat()} -->")
lines.append("")

for entry in turns:
    if not isinstance(entry, dict):
        continue
    if entry.get("isSidechain"):
        continue
    if entry.get("isMeta"):
        prefix = "## (meta)"
    else:
        ttype = entry.get("type")
        if ttype == "user":
            prefix = "## User"
        elif ttype == "assistant":
            prefix = "## Assistant"
        elif ttype == "system":
            prefix = "## System"
        else:
            continue

    msg = entry.get("message") or {}
    content = msg.get("content")
    text = extract_text(content).strip()
    if not text:
        continue

    ts = entry.get("timestamp", "")
    header = f"{prefix}" + (f" — {ts}" if ts else "")
    lines.append(header)
    lines.append("")
    lines.append(text)
    lines.append("")

out_path = Path(out_override) if out_override else (sessions_dir / f"{session_id}.md")
out_path.parent.mkdir(parents=True, exist_ok=True)

# Preserve any pre-existing "## Summary" block (written by summarize.sh on final stop)
existing = ""
if out_path.exists():
    try:
        existing = out_path.read_text(encoding="utf-8")
    except Exception:
        existing = ""

summary_block = ""
m = re.match(r"(.*?## Summary.*?\n\n.*?\n)(?=##\s)", existing, re.DOTALL)
if m:
    summary_block = m.group(1)

body = "\n".join(lines)
final = summary_block + body if summary_block else body
out_path.write_text(final, encoding="utf-8")
PY

exit 0
