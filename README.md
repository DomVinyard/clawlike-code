# clawlike-code

> A persistent-memory plugin for Claude Code: per-session injection, full transcripts, end-of-session summaries, and a per-turn classifier that catches what the agent forgot to write down. Inspired by [openclaw](https://docs.openclaw.ai); aligned with the [CoALA](https://arxiv.org/abs/2309.02427) framework.

## What it does

Four equal-weight features. All zero-config, all running on every session.

### 1. Memory injection (SessionStart)

Walks `.clawlike/context/*.md`, parses each file's `contract:` frontmatter, emits a `<persistent-memory>` envelope to the agent. Multi-file structure means routing edits to the right file isn't a guess — each file's contract declares what belongs.

### 2. Session transcription (Stop, every turn)

Writes every conversation to `.clawlike/sessions/<session-id>.md` — full markdown with `## User` / `## Assistant` headers, committable, greppable. Replaces ad-hoc transcript exports.

### 3. Session summarisation (Stop, final)

On the agent's last stop of a session, prepends a one-paragraph Haiku summary to the top of the session file. Future sessions can scan the headers to understand what happened previously without rereading the whole transcript.

### 4. Per-turn safety-net classifier (Stop, first)

After each turn, a fast Haiku call looks at the recent conversation + every memory file's contract and asks: *"Did the agent state a durable rule and fail to write it down?"* If yes, it:

- Writes the proposal to `MEMORY.md ## Pending Lessons` (timestamped, with target file + reasoning)
- Returns `{"decision": "block", "reason": "..."}` to Claude Code

Claude Code injects the reason as a synthetic meta-message and continues the agent loop — so the agent addresses the proposal **in the same turn** (apply it, reject it, or explain why not). The classifier is throttled by a 10-second cooldown.

## Why

Most Claude Code memory plugins either dump everything into a single `CLAUDE.md` or stuff observations into an opaque vector DB. `clawlike-code` does neither:

- **Multi-file, contract-driven.** Each memory file's `contract:` frontmatter declares its purpose. The classifier reads contracts and proposes targeted edits — no overflow, no drift.
- **CoALA-aligned.** Semantic / procedural / episodic taxonomy, the convergent shape of the agent-memory field.
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

That scaffolds `.clawlike/context/` with the 6 canonical starter files. Fill in the body of each, commit, and you're done.

## The 6 canonical files

Borrowed directly from openclaw's workspace convention:

| File | Stores | CoALA type |
|---|---|---|
| `IDENTITY.md` | Name, role, what I am. Stable facts. | Semantic |
| `SOUL.md` | Voice, character, what I won't do. **Not workflows.** | Semantic |
| `AGENTS.md` | Hard rules, SOPs, always/never. | Procedural |
| `USER.md` | Who I work with — schedule, preferences, communication style. | Semantic |
| `TOOLS.md` | Toolbelt + local cheat-sheet. | Semantic |
| `MEMORY.md` | Incident-derived lessons + the classifier's pending-proposal inbox. | Curated episodic |

### Adding your own

The plugin walks `.clawlike/context/*.md` indiscriminately — any file with a `contract:` frontmatter is loaded. Useful additions worth considering:

- **`PHYSICS.md`** — the shape of the agent's runtime: sandbox, timeouts, persistence model. Helpful for agents that run on infrastructure with non-obvious constraints.
- **`MAP.md`** — external context sources, data locations, "where do I find X" lookup table. Per the [AX](https://dom.vin/2026/ax) framing: an agent's two jobs are *use the map* and *improve the map*.
- **Topic-specific files** — `known-issues.md`, `relationships.md`, `experiments.md`. The same `contract:` pattern; the classifier will route to them if their contracts cover the case.

The `memory` skill (auto-invoked on relevant prompts) teaches the agent how to choose between files and when to suggest adding new ones.

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

Auth for `summarize.sh` and `classify.sh`: uses `$CLAUDE_SESSION_INGRESS_TOKEN_FILE` (set by Claude Code in every hook subprocess). Same Max billing as the parent session — no separate API key.

## Configuration

There isn't much. Everything is opinionated by design.

| Env var | Default | What |
|---|---|---|
| `CLAWLIKE_MODEL` | `claude-haiku-4-5-20251001` | Model used by classifier + summariser |
| `CLAWLIKE_COOLDOWN_SECS` | `10` | Min seconds between classifier runs |
| `CLAWLIKE_MAX_TURNS` | `12` | How many recent turns the classifier sees |

State that's NOT user data lives in `${XDG_CACHE_HOME:-$HOME/.cache}/clawlike-code/`. Your repo stays clean.

## Slash commands

- `/clawlike-code:init` — first-time setup, scaffolds the 6 canonical files
- `/clawlike-code:status` — shows loaded files, contracts, recent classifier activity
- `/clawlike-code:search <query>` — greps across `.clawlike/sessions/`

Plus an auto-invoked `/clawlike-code:memory` skill that teaches the agent the CoALA taxonomy, the contract convention, and how to triage pending lessons.

## Inspiration

- [**openclaw**](https://openclaw.ai) — the canonical 6-file workspace (`AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `MEMORY.md`), the per-turn classifier with brutal prompt + transcript-fork-to-/tmp, the "Text > Brain" axiom.
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
| Session transcripts in-repo | ✅ | ✗ | Tiered daily logs | ✗ |
| End-of-session summaries | ✅ | ✗ | ✅ | ✗ |

## Trade-offs

- **Auto-block can extend a "finished" turn.** When the classifier proposes an edit, the agent keeps running to address it. Usually a few seconds; rarely longer. If you want stricter session boundaries, set `CLAWLIKE_COOLDOWN_SECS` higher.
- **Classifier costs Haiku tokens.** ~$0.001 per fire, throttled by cooldown. Bound to about $0.01 per long session.
- **6 files is opinionated.** The plugin walks the directory so you can add more — but the "right way" is to make a new file with its own contract, not to bloat an existing one.
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
