#!/usr/bin/env bash
# inject.sh — walks .clawlike/context/, parses each file's `contract:`
# frontmatter, and emits a single JSON hookSpecificOutput payload to stdout
# wrapping the methodology block + per-file <layer> blocks inside a
# <persistent-memory> envelope.
#
# Stdin is ignored. Stdout is consumed by Claude Code's SessionStart hook.

set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONTEXT_DIR="$REPO_ROOT/.clawlike/context"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METHODOLOGY_FILE="$PLUGIN_DIR/methodology.md"

# No context dir → silently no-op (plugin not initialised for this repo)
if [ ! -d "$CONTEXT_DIR" ]; then
  exit 0
fi

BLOB=$(python3 - "$REPO_ROOT" "$METHODOLOGY_FILE" <<'PY'
import sys, re, html
from pathlib import Path

repo_root = Path(sys.argv[1])
methodology_path = Path(sys.argv[2])
context_dir = repo_root / ".clawlike" / "context"


def read_file(path):
    try:
        return path.read_text()
    except (FileNotFoundError, OSError):
        return None


def parse_frontmatter(text):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    fm_raw, body = m.group(1), m.group(2)
    fm = {}
    for line in fm_raw.splitlines():
        kv = re.match(r"^([\w_-]+):\s*(.*)", line)
        if kv:
            val = kv.group(2).strip()
            if len(val) >= 2 and val[0] in ("\"", "'") and val[0] == val[-1]:
                val = val[1:-1]
            fm[kv.group(1)] = val
    return fm, body


parts = ["<persistent-memory>"]

methodology = read_file(methodology_path)
if methodology is not None:
    parts.append("<methodology>")
    parts.append(methodology.strip())
    parts.append("</methodology>")
    parts.append("")

# Walk .clawlike/context/*.md alphabetically — files are the source of truth.
for path in sorted(context_dir.glob("*.md")):
    text = read_file(path)
    if text is None:
        continue
    fm, body = parse_frontmatter(text)
    contract = fm.get("contract", "")
    name = path.stem  # filename without extension
    display = f".clawlike/context/{path.name}"
    parts.append(
        f'<layer name="{name}" path="{display}" '
        f'contract="{html.escape(contract, quote=True)}">'
    )
    parts.append(body.strip())
    parts.append("</layer>")
    parts.append("")

parts.append("</persistent-memory>")

print("\n".join(parts))
PY
)

# If somehow empty, no-op.
if [ -z "$BLOB" ]; then
  exit 0
fi

jq -nc --arg c "$BLOB" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
