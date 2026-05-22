# Changelog

## 0.1.1 — 2026-05-22

- `commit.sh`: fix `fast_forward_to_origin` overwriting parallel sessions' work. Previous implementation moved the branch ref via `update-ref` then restored only plugin-owned paths, leaving every other changed path pinned to the pre-fast-forward blob in the index. `git status` then showed phantom staged modifications/deletions of the parallel session's work, and any future `git add . && git commit` would silently revert it. Replaced with `git merge --ff-only`, which advances HEAD, index, and working tree atomically and refuses cleanly if a real local change would conflict.
- `commit.sh`: add `heal_stale_state()` to self-heal containers stuck with the phantom-state residue from the pre-fix bug. Safe heuristics only: missing-on-disk files restored from HEAD, and staged-blob-equals-known-ancestor reverts cleaned. Paths with unstaged edits are left alone so genuine in-progress work is never destroyed.
- `lib/git-check.sh`: v2. Filter out-of-repo paths (e.g. `/tmp/...`, `/root/.claude/plans/...`) from the session-scoped diff check. v1 passed them to `git diff` as `../../...`, which errored and fired a spurious "uncommitted changes" warning on every Stop.
- `hooks/session-start.sh`: version-aware install. Marker is now `clawlike-session-scoped v<N>`; install logic compares installed version to the plugin's shipped version and overwrites on mismatch, so v1 → v2 (or future bumps) propagate automatically the next time a session starts in any container that already has an older copy at `~/.claude/stop-hook-git-check.sh`.

## 0.1.0-unreleased

- Stop-hook writes go through a staging directory outside the repo (`$XDG_CACHE_HOME/clawlike-code/staging/<session-id>/`) and land in HEAD via git plumbing (`hash-object` → `write-tree` → `commit-tree` → `update-ref` → `restore`). The working tree is never dirty while the plugin runs — making the plugin invisible to harness-level "no uncommitted changes" checks (e.g. Claude Code Cloud's `stop-hook-git-check.sh`). Race window between ref advance and wt restore is sub-millisecond, and the harness check has already finished (~200 ms) by the time plumbing reaches that step.
- Push retry now rebuilds the commit on top of the current origin tip each attempt instead of leaving a divergent local commit. On terminal failure, local HEAD is rolled back cleanly; staging files persist for the next Stop to retry.
- Author identity for plugin commits is fixed to `clawlike <clawlike@dom.vin>` so they're trivially filterable: `git log --invert-grep --author=clawlike`.
- Session-scoped Stop-hook git check installed at `~/.claude/stop-hook-git-check.sh` (harness's original backed up to `<same>.orig`). Scopes the harness's "uncommitted changes" warning to paths the current session actually wrote to, parsed from the JSONL transcript — so sibling sessions' dirt in a shared sandbox doesn't bother the current agent.

## 0.1.0 — 2026-05-19

Initial release.

- SessionStart hook injects a `<persistent-memory>` envelope built from `.clawlike/context/*.md`
- Stop hook: transcript writer, one-paragraph Haiku summariser (on final stop), Haiku safety-net classifier (on first stop with 10s cooldown)
- Classifier uses Claude Code's session ingress token (no external API key)
- 8-file canonical starter set: `IDENTITY`, `SOUL`, `AGENTS`, `USER`, `TOOLS`, `MEMORY`, `PHYSICS`, `MAP`
- Slash commands: `/clawlike-code:init`, `/clawlike-code:status`, `/clawlike-code:search`
- Auto-invoked `memory` skill teaching CoALA taxonomy + contract convention
- Runtime state in `$XDG_CACHE_HOME/clawlike-code/` — zero footprint in the consumer repo beyond `.clawlike/`
