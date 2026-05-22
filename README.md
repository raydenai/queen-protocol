# Queen Protocol

**An operational contract for Claude Code "queen" sessions orchestrating colonies of polymorphic worker ants** — child Claude Code sessions in tmux panes, background Kimi tasks in git worktrees, OpenAI Codex sidecars, and foreground Anthropic Agent calls.

The protocol governs dispatch, convergence, verification, and landing of parallel coding work across 6–12 concurrent shards on a single host. It is reviewed and battle-tested through three real-execution colonies and three rounds of multi-model adversarial review (Codex, Kimi, and a 3-model Perplexity council of GPT-5.5 / Claude Opus 4.7 / Gemini 3.1 Pro).

**Current version:** v2.19.1 — full version-by-version rationale lives in [CHANGELOG.md](./CHANGELOG.md). Multi-phase plan in [ROADMAP.md](./ROADMAP.md). Headline this bump: **ROADMAP.md NEW + §31 multi-phase roadmap reference + Wave A activated as dogfood of the super-queen pattern**. v2.19.0 documented the super-queen ROLE; v2.19.1 documents the multi-phase execution plan AND demonstrates the pattern by shipping itself via 3 parallel tracks: Track 1 (Claude, in-turn) writes the docs + commits; Track 2 (Kimi background, isolated worktree, pid=94024) drafts the v2.19.2 parallel verification gates implementation; Track 3 (Kimi background, isolated worktree, pid=94109) drafts the v2.19.3 cap-aware autopilot. File-disjoint, zero merge-conflict risk. The protocol's own development is now its first super-queen colony. ROADMAP covers 8 phase groups: foundation (✓), speed implementation (v2.19.x, in progress), decomposition automation (v2.20.x), cross-queen coordination (v2.21.x), colony-level verification (v2.22.x), operational UX (v2.23.x), multi-host (v3.0.x — graduates from "single-host production-ish" to multi-host), quality from learning (v3.1.x). Critical path: ~34 sessions sequential; ~18 sessions with 3-queen parallel waves. Roadmap is NOT a binding contract — real evidence re-prioritizes ruthlessly. Tracks 2 + 3 surface drafts in next session; this v2.19.1 ships docs + activation only.

**Status:** single-host, single-queen production-ish. Max-Mode default. First max-mode colony shipped 2026-05-08: 5 shards, 113 tests, 2 real bugs found, 15 min wall-clock, ~2.0× speedup vs default-mode baseline. Cross-host signaling via [`claude-mesh`](https://github.com/umitkacar/claude-mesh); multi-host fencing remains v3.

> **Max-Mode default**: colonies without an explicit `mode` field run at lightning speed. To force full-rigor verification (migrations, payment flows, auth), set `mode: "default"` or use shards with `priority: critical` / production-path tags — those auto-promote to default rules. See §25.

---

## Why this exists

Three failure modes are common when LLM agents code in parallel:

1. **The queen claims done before all gates pass.** Reports from the agents are unverified candidate work, not facts. Treating them as facts leads to broken builds, hallucinated test passes, and stale-merge corruption.
2. **The queen serializes parallelizable work.** Naive orchestration runs everything sequentially because cross-shard coordination is hard. Throughput craters.
3. **The queen spawns ants that step on each other.** Two ants writing the same file produces non-recoverable merge hell. Without a `files_allowed` invariant, the colony ships broken work or doesn't ship at all.

The Queen Protocol prevents all three.

---

## Core architecture

```text
SURVEY → PLAN → DISPATCH → WATCH → CONVERGE → VERIFY → LAND
   ↓        ↓        ↓         ↓        ↓        ↓       ↓
 lock     DAG    polymorphic   ant     queen   gates    PR
acquire  validate   workers   reports  re-runs   ✓     review
```

- **Polymorphic workers**: queen-direct / kimi-isolated / claude-ant / agent:codex-rescue / agent:kimi-rescue / meshterm pane reuse. Routed per shard via [decision function](./QUEEN_PROTOCOL.md#L415).
- **Specialist roles** (Model K): role-tuned claude-ants for domain-specific work (Stripe payments, RLS migrations, Schema.org, etc.).
- **Tournament + Branching shards** (Models L+M): parallel exploration for high-stakes or uncertain decisions.
- **Honeycomb broker** (Model R): shared-interface coordination without senior-ant serialization.
- **Recursive + hierarchical colonies** (Models J+D): scale past the ~12-shard ceiling.
- **Memory feed** (Model N): pre-PLAN retrieval + post-LAND harvest of lessons across colonies.
- **Continuous schedules** (Model T): cron-style and event-driven recurring colonies.

---

## What's enforced vs aspirational

The protocol distinguishes between **ENFORCED controls** (specific actor, deterministic mechanism, observable failure signal) and **ASPIRATIONAL design** (described intent, implementation pending). The buzzword discount rule (council finding) gates every claim.

**ENFORCED in v2.3.1:**

- Concurrent-queen lock with stale-detection (mkdir-atomic + holder.json)
- Atomic `active.json` writes (mv from .tmp)
- Six-step queen-side report validation (parse, schema, diff-truth, skill-grep, gate-rerun, conflict-pre-check)
- Files-allowed gate with auto-enforcement at converge
- Integration-worktree converge with snapshot/rollback boundary
- Semantic-injection defenses (length caps, fenced quoting, allowlist)
- Telemetry sink + per-colony metrics.json
- Worktree containment + secrets-boundary scanner

**MULTI-HOST DEFERRED to v3:**

- Resource-level Kleppmann fencing (single-host uses idempotency keys + worktree containment as the substitute)
- Lamport clocks for causal ordering (single-host uses transitions.log + monotonic timestamps)
- True distributed lock service

**ASPIRATIONAL until runtime kernel ships:**

- SLO computation infrastructure (metrics written, no aggregation script yet)
- Honeycomb broker daemon (pattern defined, not implemented)
- Scheduled colony scheduler (pattern defined, not wired)
- `colony.sh` runtime kernel itself

---

## Real metrics (3 colonies, 5 shards, 2026-05-08)

| SLI | Value | Target | Note |
|---|---|---|---|
| `shard_merge_no_retry_rate` | 100% (5/5) | ≥70% | First-try success across 3 colonies |
| `gate_rerun_pass_rate` | 100% (5/5) | ≥90% | Ants did not lie about gate results |
| `report_validation_pass_rate` | 100% (5/5) | ≥80% | All reports cleared §3.1 first try |
| `colony_no_user_intervention_rate` | 67% (2/3) | ≥85% | One PLAN-checkpoint pause (deliberate) |
| Cost-drift (agent:general-purpose) | +100% | ≤50% | Drove §17.1 calibration patch |

See [`examples/`](./examples/) for the actual metrics.json from each colony.

---

## Repo contents

- [`QUEEN_PROTOCOL.md`](./QUEEN_PROTOCOL.md) — the full protocol (1750+ lines, 25 sections)
- [`CHANGELOG.md`](./CHANGELOG.md) — version history with reviewer attribution
- [`examples/`](./examples/) — sanitized metrics.json from real dogfood colonies
- [`LICENSE`](./LICENSE) — MIT

---

## How to use

1. **Read [`QUEEN_PROTOCOL.md`](./QUEEN_PROTOCOL.md)** end-to-end once. It's long but structured; the operational entry point is §22 cheat sheet.
2. **Layer it into a Claude Code project** by referencing it from your repo-local `CLAUDE.md`. The protocol explicitly defers to repo-local CLAUDE.md on conflict.
3. **Set up state directories**: `mkdir -p ~/.claude/state/colony/{schemas,scheduled}`. Prerequisite scripts:
   - [`kimi-task.sh`](https://github.com/raydenai/kimi-task-sh) (or equivalent Kimi background-task wrapper)
   - [`codex-task.sh`](https://github.com/raydenai/codex-task-sh) (or equivalent Codex sidecar wrapper)
4. **Install the mesh-trio companion stack** for visible workers + dashboard (see §22.10):

   ```bash
   pip install meshterm meshboard claude-mesh
   meshboard serve --port 8080 &   # browser dashboard at http://localhost:8080
   ```

   - [`meshterm`](https://github.com/umitkacar/meshterm) — iTerm2-compatible tmux automation (powers claude-ant dispatch)
   - [`claude-mesh`](https://github.com/umitkacar/claude-mesh) — cross-platform inter-session signaling (5 transports, 3 signal layers)
   - [`meshboard`](https://github.com/umitkacar/meshboard) — real-time observation dashboard with WebSocket fan-out + SQLite WAL event store

5. **Acquire lock + run a small audit colony first** before any write-shard colonies — proves the cycle works in your environment. Pattern in §22.1–22.7.

---

## Reviewer credits

This protocol exists because three independent review passes found things a single author missed:

- **v2 → v2.1**: [Codex](https://openai.com/codex) (technical lens) + [Moonshot Kimi](https://www.kimi.com) (operational lens)
- **v2.2 council**: GPT-5.5 Thinking + Claude Opus 4.7 Thinking + Gemini 3.1 Pro Thinking (via Perplexity Pro)
- **v2.3.1 calibration**: real-execution metrics from 3 colonies on 2026-05-08

The "buzzword discount rule" — every claimed control must specify (a) actor, (b) mechanism, (c) failure response, (d) observability — was contributed by GPT-5.5 Thinking and applied retroactively to scope §18 distsys claims honestly.

---

## License

MIT — see [LICENSE](./LICENSE).

---

> **The queen who follows this protocol ships verified work fast.**
> **The queen who skips steps either ships broken work or ships slowly.**
> **The protocol exists so the queen doesn't have to remember which.**
