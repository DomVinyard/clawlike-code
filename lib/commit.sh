#!/usr/bin/env bash
# commit.sh — race-free commit and push of plugin writes.
#
# Why plumbing instead of `git add && git commit`:
# In Claude Code Cloud, a harness-level Stop hook checks for uncommitted
# changes and yells if the working tree is dirty. Both the harness check
# and this plugin's Stop hook fire in parallel. If we wrote files to the
# working tree via `transcribe.sh` and `classify.sh` (which takes ~5s
# because of the Haiku call), the harness check would sample the dirty
# state and warn the agent on every turn — cosmetic but constant noise.
#
# The fix: never put plugin writes in the working tree until they're
# already in HEAD. `transcribe.sh` and `classify.sh` write to a staging
# directory outside the repo. This script:
#   1. Fetches origin to learn the current remote tip.
#   2. Fast-forwards local HEAD to origin if origin is ahead and our
#      branch hasn't diverged (cheap, atomic ref move).
#   3. Hashes each staging file into a git blob (`git hash-object -w`).
#   4. Builds a temporary index seeded from HEAD, adds the new blobs.
#   5. Writes the tree (`git write-tree` with GIT_INDEX_FILE).
#   6. Creates the commit (`git commit-tree`).
#   7. Atomically advances the branch ref (`git update-ref`).
#   8. Restores the working tree for plugin paths only
#      (`git restore --source HEAD --staged --worktree -- <paths>`).
#   9. Pushes. On non-fast-forward, loops back to (1) and rebuilds.
#
# Race window between (7) and (8) is sub-millisecond — and irrelevant
# anyway, because the harness check has already finished (~200 ms) long
# before this script even reaches the plumbing phase (~5 s in).
#
# Usage:
#   commit.sh <session_id> <session_staged_path> <memory_staged_path>
#
# Arguments may be empty strings; missing/empty paths are skipped. If
# nothing differs from HEAD, the script exits 0 silently.
#
# Author identity is fixed to clawlike <clawlike@dom.vin> so the commits
# are trivially filterable:  git log --invert-grep --author=clawlike
#
# Failures are swallowed — staging files persist for the next Stop to
# retry. Always exits 0.

set -uo pipefail

SESSION_ID="${1:-}"
SESSION_STAGED="${2:-}"
MEMORY_STAGED="${3:-}"

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$REPO_ROOT" 2>/dev/null || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
[ -z "$BRANCH" ] && exit 0

# Determine the working-tree paths these blobs belong at.
SESSION_PATH=""
[ -n "$SESSION_ID" ] && [ -n "$SESSION_STAGED" ] && [ -f "$SESSION_STAGED" ] && \
  SESSION_PATH=".clawlike/sessions/${SESSION_ID}.md"

MEMORY_PATH=""
[ -n "$MEMORY_STAGED" ] && [ -f "$MEMORY_STAGED" ] && \
  MEMORY_PATH=".clawlike/context/MEMORY.md"

[ -z "$SESSION_PATH" ] && [ -z "$MEMORY_PATH" ] && exit 0

RESTORE_PATHS=()
[ -n "$SESSION_PATH" ] && RESTORE_PATHS+=("$SESSION_PATH")
[ -n "$MEMORY_PATH" ]  && RESTORE_PATHS+=("$MEMORY_PATH")

# Temp index used for plumbing. Lives in /tmp so it never touches the
# real .git/index (which may be in use by the agent or other tools).
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT

head_blob_at() {
  git ls-tree HEAD -- "$1" 2>/dev/null | awk '{print $3}'
}

# fast_forward_to_origin: if origin/<branch> is strictly ahead of our HEAD
# (i.e. we're a strict ancestor of origin), advance HEAD to origin and
# restore wt for plugin paths so the next build operates on the latest
# state. If we've diverged (we have local commits origin doesn't), do
# nothing — preserve the user's work.
fast_forward_to_origin() {
  git fetch --quiet origin "$BRANCH" 2>/dev/null || return 0
  local origin_sha
  origin_sha=$(git rev-parse "refs/remotes/origin/$BRANCH" 2>/dev/null || true)
  [ -z "$origin_sha" ] && return 0
  local head_sha
  head_sha=$(git rev-parse HEAD)
  [ "$head_sha" = "$origin_sha" ] && return 0
  # Only fast-forward if we're a strict ancestor (no local divergence).
  if git merge-base --is-ancestor "$head_sha" "$origin_sha" 2>/dev/null; then
    git update-ref "refs/heads/$BRANCH" "$origin_sha" "$head_sha" 2>/dev/null || return 0
    if [ "${#RESTORE_PATHS[@]}" -gt 0 ]; then
      if ! git restore --source HEAD --staged --worktree -- "${RESTORE_PATHS[@]}" 2>/dev/null; then
        git checkout HEAD -- "${RESTORE_PATHS[@]}" 2>/dev/null || true
      fi
    fi
  fi
}

# build_and_push: builds a commit on top of current HEAD from the
# staging files and pushes it. Returns 0 on success, non-zero on push
# failure (caller decides whether to retry).
build_and_push() {
  local head_commit
  head_commit=$(git rev-parse HEAD 2>/dev/null) || return 1

  # Hash blobs (no wt/index side effects).
  local new_session_blob="" new_memory_blob=""
  if [ -n "$SESSION_PATH" ]; then
    new_session_blob=$(git hash-object -w "$SESSION_STAGED" 2>/dev/null || true)
  fi
  if [ -n "$MEMORY_PATH" ]; then
    new_memory_blob=$(git hash-object -w "$MEMORY_STAGED" 2>/dev/null || true)
  fi

  # Compare against HEAD's tree. If nothing differs, skip.
  local head_session_blob="" head_memory_blob=""
  [ -n "$SESSION_PATH" ] && head_session_blob=$(head_blob_at "$SESSION_PATH")
  [ -n "$MEMORY_PATH" ]  && head_memory_blob=$(head_blob_at  "$MEMORY_PATH")

  local changed=0
  [ -n "$new_session_blob" ] && [ "$new_session_blob" != "$head_session_blob" ] && changed=1
  [ -n "$new_memory_blob" ]  && [ "$new_memory_blob"  != "$head_memory_blob" ]  && changed=1
  [ "$changed" -eq 0 ] && return 0  # nothing to do, treated as success

  # Build the new tree.
  : > "$TMP_INDEX"
  GIT_INDEX_FILE="$TMP_INDEX" git read-tree HEAD 2>/dev/null || return 1
  if [ -n "$new_session_blob" ]; then
    GIT_INDEX_FILE="$TMP_INDEX" git update-index --add \
      --cacheinfo "100644,$new_session_blob,$SESSION_PATH" 2>/dev/null || return 1
  fi
  if [ -n "$new_memory_blob" ]; then
    GIT_INDEX_FILE="$TMP_INDEX" git update-index --add \
      --cacheinfo "100644,$new_memory_blob,$MEMORY_PATH" 2>/dev/null || return 1
  fi
  local tree
  tree=$(GIT_INDEX_FILE="$TMP_INDEX" git write-tree 2>/dev/null) || return 1
  [ -z "$tree" ] && return 1

  local new_commit
  new_commit=$(GIT_AUTHOR_NAME=clawlike \
               GIT_AUTHOR_EMAIL=clawlike@dom.vin \
               GIT_COMMITTER_NAME=clawlike \
               GIT_COMMITTER_EMAIL=clawlike@dom.vin \
    git commit-tree "$tree" -p "$head_commit" -m "memory: session writes" 2>/dev/null)
  [ -z "$new_commit" ] && return 1

  # Atomically advance the branch ref. The old-SHA guard means this
  # fails cleanly if another local process moved the ref.
  git update-ref "refs/heads/$BRANCH" "$new_commit" "$head_commit" 2>/dev/null || return 1

  # Restore working tree for plugin paths.
  if [ "${#RESTORE_PATHS[@]}" -gt 0 ]; then
    if ! git restore --source HEAD --staged --worktree -- "${RESTORE_PATHS[@]}" 2>/dev/null; then
      git checkout HEAD -- "${RESTORE_PATHS[@]}" 2>/dev/null || true
    fi
  fi
  # Defensive fallback if somehow the wt file ended up missing.
  if [ -n "$SESSION_PATH" ] && [ ! -f "$SESSION_PATH" ]; then
    mkdir -p "$(dirname "$SESSION_PATH")"
    cp "$SESSION_STAGED" "$SESSION_PATH" 2>/dev/null || true
  fi
  if [ -n "$MEMORY_PATH" ] && [ ! -f "$MEMORY_PATH" ]; then
    mkdir -p "$(dirname "$MEMORY_PATH")"
    cp "$MEMORY_STAGED" "$MEMORY_PATH" 2>/dev/null || true
  fi

  # Push. If origin advanced underneath us, this fails; caller decides
  # whether to roll back and rebuild on a fresher HEAD.
  if git push --quiet origin "$BRANCH" 2>/dev/null; then
    return 0
  fi

  # Push failed. Roll back local HEAD so we don't leave a divergent branch.
  git update-ref "refs/heads/$BRANCH" "$head_commit" 2>/dev/null || true
  if [ "${#RESTORE_PATHS[@]}" -gt 0 ]; then
    if ! git restore --source HEAD --staged --worktree -- "${RESTORE_PATHS[@]}" 2>/dev/null; then
      git checkout HEAD -- "${RESTORE_PATHS[@]}" 2>/dev/null || true
    fi
  fi
  return 1
}

# Main loop: fast-forward, then attempt build+push. On failure, retry —
# the next iteration will fast-forward to whatever origin has now and
# rebuild the commit on top of it.
for attempt in 1 2 3; do
  fast_forward_to_origin
  if build_and_push; then
    [ -n "$SESSION_STAGED" ] && rm -f "$SESSION_STAGED" 2>/dev/null
    [ -n "$MEMORY_STAGED" ]  && rm -f "$MEMORY_STAGED"  2>/dev/null
    exit 0
  fi
  sleep $((attempt))
done

exit 0
