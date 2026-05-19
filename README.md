# clawlike-code

> Persistent memory for Claude Code. Contract-aware routing across a canonical 8-file memory tree. Inspired by [openclaw](https://docs.openclaw.ai) and the [CoALA](https://arxiv.org/abs/2309.02427) framework.

## What it does

Four things, on every session, with zero config:

1. **Injects** your memory files at SessionStart — `IDENTITY`, `SOUL`, `AGENTS`, `USER`, `TOOLS`, `MEMORY`, `PHYSICS`, `MAP`. Each declares its own `contract:` in frontmatter, so the agent knows what belongs in each file.
2. **Transcribes** every session to `.clawlike/sessions/<id>.md` — full markdown, committable, greppable.
3. **Summarises** finished sessions into a one-paragraph header (via Haiku, ~2 seconds).
4. **Classifies** what the agent learned each turn. If you state a durable rule and forget to write it down, the classifier proposes the edit to `MEMORY.md ## Pending Lessons` and returns `decision: "block"` so the agent addresses it before the turn truly ends.

## Why

Most Claude Code memory plugins either dump everything into a single `CLAUDE.md` or stuff observations into an opaque vector DB. `clawlike-code` does neither:

- **Multi-file, contract-driven.** Each memory file's `contract:` frontmatter declares its purpose. The classifier reads contracts and proposes targeted edits — no overflow, no drift.
- **CoALA-aligned.** Semantic / procedural / episodic taxonomy, the convergent shape of the agent-memory field. The 8-file canonical set (openclaw 6 + 2 extensions) maps cleanly onto it.
- **Repo-native.** Everything lives in markdown files in your repo. No daemons, no vector DBs, no external secrets. Git is the persistence layer.
- **Zero-config.** No API keys, no env vars, no setup file. Auth piggybacks on Claude Code's session ingress token, so cost is on whatever billing you're already using.

## Install

```bash
/plugin install clawlike-code
```

Then in any Claude Code session:

```
/clawlike-code:init
```

That scaffolds `.clawlike/context/` with the 8 starter files. Fill in the body of each (each ships with a contract describing what belongs and what doesn't), commit, and you're done. Every future session injects them automatically.

## The 8 canonical files

| File | Stores | CoALA type |
|---|---|---|
| `IDENTITY.md` | Name, role, what I am. Stable facts. | Semantic |
| `SOUL.md` | Voice, character, what I won't do. **Not workflows.** | Semantic |
| `AGENTS.md` | Hard rules, SOPs, always/never. | Procedural |
| `USER.md` | Who I work with — schedule, preferences, communication style. | Semantic |
| `TOOLS.md` | Toolbelt + local cheat-sheet. | Semantic |
| `MEMORY.md` | Incident-derived lessons + the classifier's pending-proposal inbox. | Curated episodic |
| `PHYSICS.md` | Sandbox / time / persistence model. The world I run in. | Semantic |
| `MAP.md` | External context sources — data locations, access paths. | Semantic |

Add your own. The plugin walks `.clawlike/context/*.md` indiscriminately — any file with a `contract:` frontmatter is loaded.

## How the classifier works

After every Stop hook, the plugin:

1. Cooldown gate (10s default; skips if a classifier ran recently for this user)
2. Forks the session JSONL transcript to `/tmp/` — avoids file-lock contention with the live session
3. Sends the recent turns + every memory file's contract to Haiku with a brutal "you are NOT the assistant, you are a memory-routing classifier" prompt
4. If the model proposes an edit (`TARGET: <file>; ENTRY: <line>; REASON: <why>`):
   - Appends a timestamped entry to `MEMORY.md ## Pending Lessons`
   - Returns `{"decision": "block", "reason": "..."}` to Claude Code
5. Claude Code injects the reason as a synthetic meta-message and continues the agent loop — so the agent addresses the proposal in the same turn (apply it, reject it, or explain why not)

The classifier is a **safety net**, not the primary mechanism. The primary mechanism is the agent's own discipline (the "Text > Brain — write it to a file NOW" axiom in `methodology.md`). The classifier catches what the agent forgets.

## Architecture

Two hooks. Zero daemons. Zero vector DBs.

```
SessionStart hook
└─ lib/inject.sh
   ├─ walks .clawlike/context/*.md
   ├─ parses each file's contract: frontmatter
   └─ emits <persistent-memory> envelope (methodology + per-file <layer> blocks)

Stop hook
├─ lib/transcribe.sh   — always: append turn to .clawlike/sessions/<id>.md
├─ lib/summarize.sh    — on final stop: prepend one-paragraph Haiku summary
└─ lib/classify.sh     — on first stop: cooldown → fork transcript → Haiku classifier
                          → write proposal to MEMORY.md ## Pending Lessons
                          → emit decision:block to surface the proposal mid-turn
```

Auth for `summarize.sh` and `classify.sh`: uses `$CLAUDE_SESSION_INGRESS_TOKEN_FILE` (set by Claude Code in every hook subprocess). Same Max billing as the parent session, no separate API key.

## Configuration

There isn't much. Everything is opinionated by design.

| Env var | Default | What |
|---|---|---|
| `CLAWLIKE_MODEL` | `claude-haiku-4-5-20251001` | Model used by classifier + summariser |
| `CLAWLIKE_COOLDOWN_SECS` | `10` | Min seconds between classifier runs |
| `CLAWLIKE_MAX_TURNS` | `12` | How many recent turns the classifier sees |

State that's NOT user data lives in `${XDG_CACHE_HOME:-$HOME/.cache}/clawlike-code/`. Your repo stays clean.

## Slash commands

- `/clawlike-code:init` — first-time setup, scaffolds the 8 starter files
- `/clawlike-code:status` — shows loaded files, contracts, recent classifier activity
- `/clawlike-code:search <query>` — greps across `.clawlike/sessions/`

Plus an auto-discovered `/clawlike-code:memory` skill that teaches the model the CoALA taxonomy, the contract convention, and how to triage pending lessons.

## Inspiration

- [**openclaw**](https://openclaw.ai) — the workspace-file pattern (`AGENTS.md`, `SOUL.md`, `MEMORY.md`), the per-turn classifier with brutal prompt + transcript-fork-to-/tmp, the "Text > Brain" axiom.
- [**CoALA**](https://arxiv.org/abs/2309.02427) (Princeton, 2023) — the semantic / procedural / episodic taxonomy used by every serious agent-memory library.
- [**Letta**](https://www.letta.com) (formerly MemGPT) — the memory-block model: `label` + `description` (= contract) drive routing.

## Comparison

|  | clawlike-code | [claude-mem](https://github.com/thedotmack/claude-mem) | [Remember (Anthropic)](https://claude.com/plugins/remember) | [Evolving Lite](https://github.com/primeline-ai/evolving-lite) |
|---|---|---|---|---|
| Multi-file routing via contracts | ✅ | ✗ | ✗ | ✗ |
| Markdown-only persistence | ✅ | ✗ (SQLite + Chroma) | ✅ | ✅ |
| External daemons | None | Bun daemon on :37777 | None | None |
| External secrets | None | None | None | None |
| Per-turn safety-net classifier | ✅ | ✗ | ✗ | Stop hook only |
| Surfaces proposals mid-turn | ✅ via `decision: "block"` | N/A | N/A | N/A |

## Trade-offs

- **Auto-block can extend a "finished" turn.** When the classifier proposes an edit, the agent keeps running to address it. Usually a few seconds; rarely longer. If you want stricter session boundaries, set `CLAWLIKE_COOLDOWN_SECS` higher.
- **Classifier costs Haiku tokens.** ~$0.001 per fire, throttled by cooldown. Bound to about $0.01 per long session.
- **8 files is opinionated.** The plugin walks the directory, so you can add more — but the "right way" is to make a new file with its own contract, not to bloat an existing one.
- **No vector recall.** Episodic transcripts are grep-only via `/clawlike-code:search`. For semantic search across years of sessions you'd want a different tool layered on top.

## Development

```bash
git clone https://github.com/DomVinyard/clawlike-code
cd clawlike-code
claude --plugin-dir .
```

Reload after edits with `/reload-plugins`.

## Licence

MIT — see [LICENSE](./LICENSE).
