#!/usr/bin/env bash
# commit.sh — commit and push the plugin's own writes.
#
# Scope: .clawlike/sessions/ and .clawlike/context/MEMORY.md only.
# These are the paths the plugin's Stop hook writes to. Committing them here
# (rather than waiting for the agent to commit them later) closes the gap
# between "plugin wrote a file" and "file survives sandbox reclaim" in
# ephemeral cloud sandboxes (Claude Code Web/Mobile, harness, etc.).
#
# Author identity is fixed (clawlike <clawlike@dom.vin>) so the commits are
# trivially filterable from `git log`:
#   git log --invert-grep --author=clawlike
#
# All output is silenced. Failures are swallowed — the next Stop hook will
# retry. Always exits 0.

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$REPO_ROOT" 2>/dev/null || exit 0

# Must be a git repo.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Detached HEAD or unborn branch → skip.
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
[ -z "$BRANCH" ] && exit 0

# Only stage paths the plugin owns. Filter to those that exist.
PATHS=()
[ -e ".clawlike/sessions" ] && PATHS+=(".clawlike/sessions")
[ -e ".clawlike/context/MEMORY.md" ] && PATHS+=(".clawlike/context/MEMORY.md")
[ "${#PATHS[@]}" -eq 0 ] && exit 0

# Stage. Use -- separator for safety.
git add -- "${PATHS[@]}" >/dev/null 2>&1 || exit 0

# Anything actually staged? --quiet returns non-zero if there are staged changes.
if git diff --cached --quiet -- "${PATHS[@]}" 2>/dev/null; then
  exit 0
fi

# Commit with fixed author identity. Hooks disabled to avoid recursion if
# the user has a pre-commit hook that calls back into the plugin.
GIT_AUTHOR_NAME=clawlike \
GIT_AUTHOR_EMAIL=clawlike@dom.vin \
GIT_COMMITTER_NAME=clawlike \
GIT_COMMITTER_EMAIL=clawlike@dom.vin \
git commit --no-verify --quiet -m "memory: session writes" -- "${PATHS[@]}" \
  >/dev/null 2>&1 || exit 0

# Push with bounded retries. Rebase first to absorb concurrent commits.
# If the rebase fails (real conflict), abort and leave the commit on the
# local branch — the next Stop will retry.
for attempt in 1 2 3; do
  if git pull --rebase --quiet origin "$BRANCH" >/dev/null 2>&1 \
     && git push --quiet origin "$BRANCH" >/dev/null 2>&1; then
    exit 0
  fi
  # If a rebase is in progress, abort it so we don't leave the repo wedged.
  git rebase --abort >/dev/null 2>&1 || true
  sleep $((attempt * 2))
done

exit 0
