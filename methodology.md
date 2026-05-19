# Memory methodology

This is `clawlike-code`'s opinionated methodology — how the persistent-memory layer above works, when to write to it, and which layer to write to. It is injected at the start of every session alongside the user's context files. Do not edit; the plugin owns this.

## The contract

Each file in `.clawlike/context/` declares its purpose via a `contract:` frontmatter line. The contract is the file's authority — it states what belongs in the file, when to update it, what NOT to put there. Read the contract before writing.

## Text > Brain

If you want to remember something, **write it to a file now** — not at the end of the session, not "later", now. The trigger is learning, not session-end. The next session has no memory of this conversation. Intending to remember is not remembering. A promise in chat that isn't committed to a file is not a promise — it's a lie with a delay.

When you catch yourself saying "going forward I'll…", "I'll remember…", "from now on…", "I won't do X again…" — stop and write the behaviour to the right file in the same turn.

## The altitude stack

Memory exists at different altitudes. Altitude determines when it loads, who authors it, and how long it should last. Before writing anything, answer: *what altitude is this?*

```
↑  substrate          — model weights; you don't write here
   epistemology       — what counts as knowing; rarely changes
   methodology        — how to build good memory; this file
   .clawlike/context/ — global identity, rules, world model
   CLAUDE.md          — area-specific rules, lazy-loaded by directory
   .clawlike/sessions/ — what happened this session; episodic
↓  attention          — what gets weighted in this forward pass
```

The direction is invariant. High altitude generates low altitude. Methodology generates context. Context generates session behaviour. Session memory does not generate methodology. Never write upward.

**Layer-bleed is the root of most context degradation.** A global principle stored in a `CLAUDE.md` gets missed by sessions outside that directory. A session-specific fact stored in a context file pollutes every future session. The fix isn't better writing — it's writing at the right altitude.

## Which file to write to

Each file in `.clawlike/context/` declares its purpose via `contract:`. Read the contract; route the write. The CoALA taxonomy is a useful guide:

- **Semantic** (timeless facts about identity, the user, the world, your toolbelt) → `IDENTITY.md`, `USER.md`, `PHYSICS.md`, `TOOLS.md`, `MAP.md`
- **Voice / character** (how you communicate, tone, what you won't do — NOT workflows) → `SOUL.md`
- **Procedural** (hard rules, SOPs, always/never) → `AGENTS.md`
- **Curated lessons** (incident-derived imperatives with dates) → `MEMORY.md`
- **Episodic** (what happened this session) → `.clawlike/sessions/` (handled automatically by the plugin)

If a new class of fact doesn't fit any existing contract, **add a new context file** with its own contract. The plugin walks `.clawlike/context/` indiscriminately — any `.md` with a `contract:` frontmatter is loaded.

## When to update

- A belief genuinely shifts → update the relevant context file
- A new non-negotiable constraint is established → `AGENTS.md`
- Something you've been assuming turns out to be wrong → update + remove the stale entry
- A capability is added or removed → `TOOLS.md`
- An incident produces a lesson ("after X happened, NEVER Y") → `MEMORY.md`

**Don't write here:**
- Area-specific rules (those go in `CLAUDE.md` per directory)
- One-off session observations
- Things true only within a sub-project

## Precision standard

Good context is closer to poetry than documentation. The precise word in the precise position does work no other word could do.

- Remove qualifications ("generally", "usually", "often")
- Remove examples that narrow rather than illuminate — a good rule needs no example
- Remove redundancy — if two sentences say the same thing, cut one
- State the principle directly; no hedges

The test: if a future agent reads this and has to guess what you meant, it needs more precision, not more words.

## Pending lessons

`MEMORY.md` has a `## Pending Lessons` section. Entries land there automatically when the plugin's Stop-hook classifier notices something you should have written but didn't. **At the start of every session, scan `## Pending Lessons` and either promote each entry into the right file (and the right section of MEMORY.md) or delete it as a misfire.** Don't let pending entries accumulate.

## The recursive instruction

This file contains the instruction to write memory this way. That includes the instruction to keep your own context files current. If your methodology produces bad behaviour, fix the file, not the symptom.
