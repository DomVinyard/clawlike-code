#!/usr/bin/env bash
# clawlike-session-scoped v2
# git-check.sh — Stop-hook check, session-scoped.
#
# Replaces the harness's whole-tree check at ~/.claude/stop-hook-git-check.sh.
# Whole-tree was noisy in shared sandboxes (multiple Claude sessions writing
# concurrently) — it warned the current agent about work done by sibling
# sessions. This version scopes the "uncommitted changes" check to paths
# the CURRENT session actually wrote to (parsed from the JSONL transcript).
#
# The "unpushed commits" check stays whole-tree — unpushed work is a real
# cross-session concern worth surfacing regardless of authorship.
#
# Install: clawlike-code's SessionStart hook backs up the harness's original
# to ~/.claude/stop-hook-git-check.sh.orig and writes this file in its place.
# Re-installs are idempotent via the marker comment on line 1; the version
# tag (v1, v2, ...) triggers in-place upgrades when the plugin ships a newer
# revision.
#
# v2 fix: paths outside the repo (e.g. /tmp/, /root/.claude/plans/) are
# skipped instead of being passed to `git diff` as `../../...` — v1 passed
# them through, `git diff` errored, and the check spuriously fired
# "uncommitted changes" on every Stop. Out-of-repo paths are not git's
# concern.
#
# Fail-open on parse errors: if the transcript can't be parsed, fall back
# to the wide check so we don't silently hide real dirty work.

set -uo pipefail

input=$(cat)

# 1. Recursion gate — mirror original.
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

# 2. Not a git repo — mirror original.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# 3. No remote — mirror original.
if [ -z "$(git remote 2>/dev/null)" ]; then
  exit 0
fi

# 4. Parse transcript for paths this session wrote to.
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)

# Fall back to wide check if no transcript (preserves safety on edge cases).
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  wide_check=1
else
  wide_check=0
  session_paths=$(python3 - "$transcript_path" 2>/dev/null <<'PY'
import json, sys
from pathlib import Path

transcript = Path(sys.argv[1])
seen = set()
write_tools = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

try:
    with transcript.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            msg = obj.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue
                name = block.get("name", "")
                if name not in write_tools:
                    continue
                inp = block.get("input") or {}
                p = inp.get("file_path") or inp.get("notebook_path") or ""
                if p:
                    seen.add(p)
except Exception:
    sys.exit(2)

for p in sorted(seen):
    print(p)
PY
  )
  parse_exit=$?
  # Python exit 2 = parse failure → fall back to wide check.
  if [ $parse_exit -ne 0 ]; then
    wide_check=1
  fi
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)

# 5. Run the diff check.
if [ "$wide_check" = "1" ]; then
  # Fallback: whole-tree (preserves original behaviour).
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "There are uncommitted changes in the repository. Please commit and push these changes to the remote branch." >&2
    exit 2
  fi
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null)
  if [ -n "$untracked" ]; then
    echo "There are untracked files in the repository. Please commit and push these changes to the remote branch." >&2
    exit 2
  fi
elif [ -n "$session_paths" ]; then
  # Session-scoped: build path list relative to repo root, filtering out
  # any paths that live OUTSIDE the repo (e.g. /tmp/, /root/.claude/plans/).
  # Out-of-repo paths are not git's concern; v1 passed them to `git diff`
  # which errored and triggered a spurious "uncommitted changes" warning.
  rel_paths=()
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      "$repo_root"/*) rel="${p#"$repo_root"/}" ;;
      "$repo_root")   rel="" ;;
      /*)             rel="" ;;  # absolute path outside repo → skip
      *)              rel="$p" ;;  # already relative
    esac
    [ -n "$rel" ] && rel_paths+=("$rel")
  done <<< "$session_paths"

  if [ "${#rel_paths[@]}" -gt 0 ]; then
    # Modified or staged within session paths?
    if ! git diff --quiet -- "${rel_paths[@]}" 2>/dev/null \
       || ! git diff --cached --quiet -- "${rel_paths[@]}" 2>/dev/null; then
      echo "There are uncommitted changes in files this session edited. Please commit and push these changes to the remote branch." >&2
      exit 2
    fi
    # Untracked among session-written paths?
    for p in "${rel_paths[@]}"; do
      if [ -e "$p" ] && ! git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
        echo "There are untracked files this session created. Please commit and push these changes to the remote branch." >&2
        exit 2
      fi
    done
  fi
fi
# If session wrote nothing detectable (zero paths), skip uncommitted/untracked
# check entirely — sibling-session dirt is theirs to handle.

# 6. Unpushed commits check — whole-tree, mirror original.
current_branch=$(git branch --show-current 2>/dev/null)
if [ -n "$current_branch" ]; then
  if git rev-parse "origin/$current_branch" >/dev/null 2>&1; then
    unpushed=$(git rev-list "origin/$current_branch..HEAD" --count 2>/dev/null) || unpushed=0
    if [ "$unpushed" -gt 0 ]; then
      echo "There are $unpushed unpushed commit(s) on branch '$current_branch'. Please push these changes to the remote repository." >&2
      exit 2
    fi
  else
    unpushed=$(git rev-list "origin/HEAD..HEAD" --count 2>/dev/null) || unpushed=0
    if [ "$unpushed" -gt 0 ]; then
      echo "Branch '$current_branch' has $unpushed unpushed commit(s) and no remote branch. Please push these changes to the remote repository." >&2
      exit 2
    fi
  fi
fi

exit 0
