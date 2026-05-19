---
name: memory
description: How the persistent-memory layer works — the canonical 8-file tree at .clawlike/context/, the CoALA taxonomy (semantic / procedural / episodic), the contract: frontmatter convention, when to add a new context file, and how to triage MEMORY.md "## Pending Lessons" at session start. Triggers when the user says "add to memory", "remember this", "you keep forgetting X", "update your axioms / identity / capabilities / map", or whenever you catch yourself promising "I'll remember" — the plugin's "Text > Brain" rule kicks in here.
---

# Memory

The clawlike-code persistent-memory layer. This skill teaches you how to use it well.

## What lives where

The canonical 8-file memory tree at `.clawlike/context/`:

| File | What goes here | Taxonomy |
|---|---|---|
| `IDENTITY.md` | Name, role, what I am. Stable facts only. | Semantic |
| `SOUL.md` | Voice, tone, how I communicate, what I won't do. **Not workflows.** | Semantic |
| `AGENTS.md` | Hard rules, SOPs, always/never. The procedural file. | Procedural |
| `USER.md` | Who I work with — schedule, preferences, communication style. | Semantic |
| `TOOLS.md` | My toolbelt + local cheat-sheet. ADD on install, REMOVE on uninstall. | Semantic |
| `MEMORY.md` | Incident-derived lessons (dated). + "## Pending Lessons" section. | Curated episodic |
| `PHYSICS.md` | Sandbox, time, comms substrate, persistence model. The world I run in. | Semantic |
| `MAP.md` | External context sources — where data lives, access paths. | Semantic |

All 8 files are injected at SessionStart inside a `<persistent-memory>` envelope alongside the plugin's `methodology.md`.

## The two-second routing question

Before you write to memory, ask: **what's the contract of the file I'm about to edit?**

Read the file's `contract:` frontmatter. The contract states what belongs there and when to update. If your edit doesn't match the contract, you're picking the wrong file.

## Choosing between files

The SOUL / AGENTS / MEMORY split is the most common confusion:

- **SOUL.md** = "I am direct, I don't sycophant, I push back when wrong" → tone and character
- **AGENTS.md** = "ALWAYS verify before reporting. NEVER spend money without permission" → hard rules
- **MEMORY.md** = "On 2026-04-09 I unloaded the gateway and broke prod for 90 min. Lesson: never restart live services without explicit go-ahead" → incident-derived

If it's a rule that's existed forever and has no specific failure behind it → AGENTS.md. If it's a rule that hardened because of a specific failure → MEMORY.md (with the date). If it's about your voice or character → SOUL.md.

## When to add a new context file

The plugin walks `.clawlike/context/` indiscriminately — any `.md` with a `contract:` frontmatter is loaded. So you can add topic-specific files when the canonical 8 don't fit.

Examples:
- `known-issues.md` — a registry of upstream bugs you've hit, with workarounds
- `relationships.md` — context on specific people you work with often
- `experiments.md` — a log of running passive-income or product experiments

The trigger to add a new file: you find yourself wanting to write a class of facts that doesn't fit any existing contract. Write a 1-3 sentence `contract:` that declares the file's purpose, then add the body.

**Don't add a file for one-off content.** If it's a single fact, find the existing file whose contract is closest.

## The "## Pending Lessons" triage

`MEMORY.md` has a `## Pending Lessons` section. The plugin's Stop-hook classifier may have appended proposals there since your last session. At the start of every session, scan it. Each entry looks like:

```
### 2026-05-18 14:32 — User prefers ALL_CAPS for canonical files
- **Target file:** AGENTS.md
- **Reason:** stated as preference in turn
- **Source session:** cc-abc123
- **Proposal ID:** 1779100000-1234
```

For each pending entry:

1. **Promote** — if the entry is right: apply the edit to the target file (add the lesson to the appropriate section), then DELETE the pending entry. If the lesson is incident-derived enough to live in MEMORY.md "## Key Lessons" instead of (or in addition to) the target file, move it there.

2. **Reject** — if it's a misfire (classifier hallucinated, content was already written elsewhere, lesson isn't durable enough): just DELETE the pending entry.

**Don't let pending entries accumulate.** Triage at session start; the section should be empty by the time you start work.

## The "write it down now" rule

The plugin's `methodology.md` quotes the openclaw axiom: **"Text > Brain — if you want to remember something, write it to a file now."**

Whenever you catch yourself saying:
- "Going forward I'll…"
- "I'll remember…"
- "From now on…"
- "I won't do X again…"
- "Sorry, I'll make sure to…"

— stop and write the behaviour to the right file IN THE SAME TURN. Don't queue it; the next session has no memory of this conversation. A promise in chat that isn't committed to the repo is a lie with a delay.

The Stop-hook classifier is the safety net for when you forget. It's not a substitute — it's just the backup.

## How sessions are persisted

Episodic memory lives at `.clawlike/sessions/<session_id>.md`. The Stop hook writes this automatically — a full markdown transcript with `## User` / `## Assistant` headers. On final stop, a `## Summary` paragraph is prepended.

You don't write to `.clawlike/sessions/` yourself. The plugin owns it.

## Slash commands

- `/claw status` — show loaded context files, contract index, last 5 classifier proposals
- `/claw search <query>` — grep across `.clawlike/sessions/` for episodic recall
- `/claw init` — first-time setup (scaffolds `.clawlike/context/` from the plugin's starter set)

## Architecture (one paragraph)

`clawlike-code` is a Claude Code plugin at `.claude/plugins/clawlike-code/`. Two hooks: SessionStart injects `<persistent-memory>` (methodology + per-file `<layer>` blocks parsed from `.clawlike/context/*.md`) as `additionalContext`. Stop transcribes the turn to `.clawlike/sessions/<id>.md`, optionally summarizes on final stop, and optionally runs a Haiku safety-net classifier that appends proposals to `MEMORY.md` "## Pending Lessons" and returns `decision: "block"` with the proposal as the reason. The classifier is gated behind `CLAWLIKE_CLASSIFIER_ENABLED=1` during initial rollout.
