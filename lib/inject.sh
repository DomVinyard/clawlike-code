#!/usr/bin/env bash
# inject.sh — walks .clawlike/context/, parses each file's `contract:`
# frontmatter, and emits a single JSON hookSpecificOutput payload to stdout
# wrapping the methodology block + per-file <layer> blocks inside a
# <persistent-memory> envelope.
#
# Token-budget-aware: if the assembled envelope exceeds CLAWLIKE_MAX_TOKENS
# (default 30000, ~ chars/3.5), the largest file bodies are truncated in
# place — contract: frontmatter is preserved so the classifier still knows
# what each file is for, and the agent can read the full file directly when
# it needs the body.
#
# Stdin is ignored. Stdout is consumed by Claude Code's SessionStart hook.

set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONTEXT_DIR="$REPO_ROOT/.clawlike/context"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METHODOLOGY_FILE="$PLUGIN_DIR/methodology.md"
MAX_TOKENS="${CLAWLIKE_MAX_TOKENS:-30000}"

# No context dir → silently no-op (plugin not initialised for this repo)
if [ ! -d "$CONTEXT_DIR" ]; then
  exit 0
fi

BLOB=$(python3 - "$REPO_ROOT" "$METHODOLOGY_FILE" "$MAX_TOKENS" <<'PY'
import sys, re, html
from pathlib import Path

repo_root = Path(sys.argv[1])
methodology_path = Path(sys.argv[2])
max_tokens = int(sys.argv[3])
context_dir = repo_root / ".clawlike" / "context"

# Rough char-to-token ratio. Conservative side: 3.5 chars per token (English
# leans 4; we err toward truncating slightly earlier).
CHARS_PER_TOKEN = 3.5
max_chars = int(max_tokens * CHARS_PER_TOKEN)


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


# --- Build the layer list (name, contract, body, display path) ---
methodology = (read_file(methodology_path) or "").strip()

layers = []  # each: {"name", "display", "contract", "body", "truncated"}
for path in sorted(context_dir.glob("*.md")):
    text = read_file(path)
    if text is None:
        continue
    fm, body = parse_frontmatter(text)
    layers.append({
        "name": path.stem,
        "display": f".clawlike/context/{path.name}",
        "contract": fm.get("contract", ""),
        "body": body.strip(),
        "truncated": False,
    })


def render():
    parts = ["<persistent-memory>"]
    if methodology:
        parts += ["<methodology>", methodology, "</methodology>", ""]
    for layer in layers:
        parts.append(
            f'<layer name="{layer["name"]}" path="{layer["display"]}" '
            f'contract="{html.escape(layer["contract"], quote=True)}">'
        )
        parts.append(layer["body"])
        parts.append("</layer>")
        parts.append("")
    parts.append("</persistent-memory>")
    return "\n".join(parts)


# --- Token-budget guard ---
# If under budget: ship as-is.
# Else: truncate largest body, repeat until under budget. Keep methodology
# and all contract: frontmatter intact (they're the routing surface).

def truncation_notice(layer, orig_bytes):
    return (
        f"[truncated to fit prompt budget — {orig_bytes:,} bytes elided. "
        f"Read {layer['display']} directly for the full body. "
        f"Contract preserved above is the file's authoritative purpose.]"
    )


rendered = render()
truncations = []
while len(rendered) > max_chars:
    # Find the longest un-truncated body. Don't touch already-truncated layers.
    candidates = [l for l in layers if not l["truncated"]]
    if not candidates:
        break  # everything's truncated; we can't shrink further without dropping the methodology
    target = max(candidates, key=lambda l: len(l["body"]))
    orig_bytes = len(target["body"])
    target["body"] = truncation_notice(target, orig_bytes)
    target["truncated"] = True
    truncations.append((target["name"], orig_bytes))
    rendered = render()

# Emit a budget banner at the top if anything was truncated, so the agent
# knows context was elided and can re-read directly.
if truncations:
    truncated_names = ", ".join(f"{n} ({b:,}B)" for n, b in truncations)
    banner = (
        f"<budget-warning>\n"
        f"Memory envelope exceeded budget ({max_tokens:,} tokens / "
        f"{max_chars:,} chars). Truncated bodies: {truncated_names}. "
        f"Read those files directly when their content is needed.\n"
        f"</budget-warning>\n\n"
    )
    rendered = rendered.replace(
        "<persistent-memory>\n", f"<persistent-memory>\n{banner}", 1
    )

print(rendered)
PY
)

# If somehow empty, no-op.
if [ -z "$BLOB" ]; then
  exit 0
fi

jq -nc --arg c "$BLOB" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
