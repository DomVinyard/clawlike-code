---
description: Grep across .clawlike/sessions/ for episodic recall. Usage = /claw search <query>
---

The user wants to search past session transcripts for: $ARGUMENTS

Run a grep across `.clawlike/sessions/*.md` for the query above. Be flexible — match case-insensitively, show ~3 lines of context around each hit, and prefer recent sessions if the query is ambiguous.

```bash
grep -i -r -A 3 -B 1 --include='*.md' "$ARGUMENTS" .clawlike/sessions/ | head -60
```

Summarise findings in 2-3 sentences. If nothing matches, say so honestly. If many matches, surface the 3 most useful (recent + topical) by filename.
