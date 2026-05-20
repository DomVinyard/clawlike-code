# Changelog

## Unreleased

- Stop hook now commits and pushes its own writes (`.clawlike/sessions/<id>.md`, `.clawlike/context/MEMORY.md`) under a fixed `clawlike <clawlike@dom.vin>` identity. Closes the data-loss gap in ephemeral cloud sandboxes (Claude Code Web/Mobile, harness) where plugin writes happen after the agent's last commit. Scoped to plugin-owned paths only; user files are never touched. Filter from history with `git log --invert-grep --author=clawlike`.

## 0.1.0 — 2026-05-19

Initial release.

- SessionStart hook injects a `<persistent-memory>` envelope built from `.clawlike/context/*.md`
- Stop hook: transcript writer, one-paragraph Haiku summariser (on final stop), Haiku safety-net classifier (on first stop with 10s cooldown)
- Classifier uses Claude Code's session ingress token (no external API key)
- 8-file canonical starter set: `IDENTITY`, `SOUL`, `AGENTS`, `USER`, `TOOLS`, `MEMORY`, `PHYSICS`, `MAP`
- Slash commands: `/clawlike-code:init`, `/clawlike-code:status`, `/clawlike-code:search`
- Auto-invoked `memory` skill teaching CoALA taxonomy + contract convention
- Runtime state in `$XDG_CACHE_HOME/clawlike-code/` — zero footprint in the consumer repo beyond `.clawlike/`
