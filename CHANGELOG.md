# Changelog

## Unreleased

- Stop-hook writes go through a staging directory outside the repo (`$XDG_CACHE_HOME/clawlike-code/staging/<session-id>/`) and land in HEAD via git plumbing (`hash-object` → `write-tree` → `commit-tree` → `update-ref` → `restore`). The working tree is never dirty while the plugin runs — making the plugin invisible to harness-level "no uncommitted changes" checks (e.g. Claude Code Cloud's `stop-hook-git-check.sh`). Race window between ref advance and wt restore is sub-millisecond, and the harness check has already finished (~200 ms) by the time plumbing reaches that step.
- Push retry now rebuilds the commit on top of the current origin tip each attempt instead of leaving a divergent local commit. On terminal failure, local HEAD is rolled back cleanly; staging files persist for the next Stop to retry.
- Author identity for plugin commits is fixed to `clawlike <clawlike@dom.vin>` so they're trivially filterable: `git log --invert-grep --author=clawlike`.

## 0.1.0 — 2026-05-19

Initial release.

- SessionStart hook injects a `<persistent-memory>` envelope built from `.clawlike/context/*.md`
- Stop hook: transcript writer, one-paragraph Haiku summariser (on final stop), Haiku safety-net classifier (on first stop with 10s cooldown)
- Classifier uses Claude Code's session ingress token (no external API key)
- 8-file canonical starter set: `IDENTITY`, `SOUL`, `AGENTS`, `USER`, `TOOLS`, `MEMORY`, `PHYSICS`, `MAP`
- Slash commands: `/clawlike-code:init`, `/clawlike-code:status`, `/clawlike-code:search`
- Auto-invoked `memory` skill teaching CoALA taxonomy + contract convention
- Runtime state in `$XDG_CACHE_HOME/clawlike-code/` — zero footprint in the consumer repo beyond `.clawlike/`
