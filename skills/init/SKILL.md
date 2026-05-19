---
description: First-time setup — scaffold .clawlike/context/ from the plugin's starter 8-file template set.
---

Check whether `.clawlike/context/` already has files. If it does, abort and explain that init is for fresh repos only.

If empty (or doesn't exist):
1. Create `.clawlike/context/` and `.clawlike/sessions/`.
2. Copy each file from `.claude/plugins/clawlike-code/starter/context/` into `.clawlike/context/`.
3. Verify the 8 canonical files landed: `IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`, `MEMORY.md`, `PHYSICS.md`, `MAP.md`.
4. Remind the user to edit each file — they ship as templates with the `contract:` frontmatter filled but placeholder bodies.
5. Suggest editing `IDENTITY.md` first (who am I + what do I do) and `USER.md` (who am I working with).

Report what was created.
