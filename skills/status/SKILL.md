---
description: Show the loaded context files, contract index, and recent classifier activity for the clawlike-code memory layer.
---

Run these checks and report concisely:

1. List the files in `.clawlike/context/` with their `contract:` frontmatter (use `head -3` on each `.md` file to extract the YAML).
2. Show file sizes (`ls -la .clawlike/context/`).
3. Count `.clawlike/sessions/*.md` files.
4. Show the most recent 5 entries from `MEMORY.md` "## Pending Lessons" (if any).
5. Show the cooldown state: when was `.clawlike/.cooldown` last touched?
6. State whether `CLAWLIKE_CLASSIFIER_ENABLED` and `CLAWLIKE_SUMMARIZER_ENABLED` are set.

Format as a one-screen summary. No prose explanation — just the facts.
