# Queen Protocol

**An operational contract for Claude Code "queen" sessions orchestrating colonies of polymorphic worker ants** — child Claude Code sessions in tmux panes, background Kimi tasks in git worktrees, OpenAI Codex sidecars, and foreground Anthropic Agent calls.

The protocol governs dispatch, convergence, verification, and landing of parallel coding work across 6–12 concurrent shards on a single host. It is reviewed and battle-tested through three real-execution colonies and three rounds of multi-model adversarial review (Codex, Kimi, and a 3-model Perplexity council of GPT-5.5 / Claude Opus 4.7 / Gemini 3.1 Pro).

**Current version:** v2.15.5 (Grok Build CODING lane added — xAI's official `grok` CLI v0.1.211 wrapped via `~/.claude/scripts/grok-build-task.sh`. Native features exposed: Plan Mode (`--permission-mode plan`), built-in worktree (`-w`), best-of-N parallel attempts (`--best-of-n N`), self-verification loop (`--check`), sandbox profiles, cross-session memory, MCP. Coexists with the existing LCV-fork `grok-task.sh` (retained for trends/x-search/roast/redteam INTEL + xAI Batch API access — Grok Build doesn't expose a batch verb). Sidecar-health.sh now reports **7-way dispatch** (Claude+Kimi+Codex+Gemini+Grok-intel+Jules-async+Grok-Build-coding). Routing recommendation (provisional, not yet a §4.2 rule): prefer Grok Build for new coding work; keep LCV fork for established specialty intel surface. SuperGrok Heavy subscription required (~$99-300/mo). Skill-bomb mitigation via `/tmp/grok-build-safe-*` cwd (identical to LCV fork). `is_grok_build_alive` PID-reuse-safe helper applied from inception. v2.15.4 (prior turn) shipped two doc-only additions: **§1.3 In-turn polling and continue-loop discipline** + **§29.16 Isolation-bypass via absolute path in prompt**. §1.3 codifies the rule that the queen MUST poll background-agent output every 60-120s within the same turn, surface one-line progress, continue executing the plan in parallel, and integrate results inline — never close a turn with `"running in background"` as the result. Rule triple-redundantly stored in `~/.claude/CLAUDE.md` hard-rules (global, every Claude Code SessionStart), project memory `feedback_queen_in_turn_polling.md` (durable across project sessions), and this protocol document (canonical). Evidence: user feedback 2026-05-12 — `"agents are running but no update and no autonomous work"` was a real value-prop failure. §29.16 documents the isolation-bypass failure mode where Kimi A-redux (PID 21551, 2026-05-12) ignored its isolated worktree and wrote 5 files directly to `~/projects/speakerport-v2/` because the prompt contained that absolute path — `--isolated` guarantee, §29.15 base-staleness gate, and dispatch-lock all silently bypassed. Rule: dispatch prompts MUST NOT contain absolute paths to operator working repos. Pre-dispatch sanitizer (auto-rewrite absolute paths to worktree paths) deferred until n≥2 evidence on another lane. Anti-fix held: no BLOCK on detection — sanitize+warn is the right intervention. Dropped from inventory: `jules-task.sh notify` was on the gap list but the parallel sidecar had already built it. v2.15.3 (Kimi-review-driven hardening of v2.15.x runtime scripts — bundles 5 fixes: (1) `kimi-task.sh` §29.15 gate TOCTOU mitigation re-samples `MAIN_HEAD` immediately before `git apply` with one-line drift warning, (2) unquoted-variable bug in user-facing hint fixed via `printf` to preserve embedded whitespace in paths with spaces, (3) exit-code 7 now documented inline at refusal time, (4) `jules-task.sh` `ensure_logged_in` regex broadened beyond the literal `"forget to login"` string to cover `"not logged in" / "valid client" / "authentication required|failed" / "unauthori[sz]ed"` so future Jules CLI message changes don't hide the actionable login prompt, (5) `is_kimi_alive` case-sensitivity fix (originally drafted as v2.15.2) — macOS `ps` returns `"Kimi Code"` with capital K + space; lowercase via `tr` before glob match. Kimi review pass (~12 min, 0 CRITICAL, 4 IMPORTANT all addressed). Codex review attempted in parallel but the `codex:codex-rescue` plugin's helper failed with "Codex CLI is not installed" despite `codex-cli 0.125.0` being on PATH — known path/version discrepancy worth filing separately. Honest single-lane review evidence for this bump. v2.15.1 (§29.15 base-staleness gate) and v2.15.0 (queen-per-session architecture) shipped earlier in the same session. in `kimi-task.sh merge` closes the **cross-colony duplicate-dispatch** failure mode. Real evidence (2026-05-12): 4 UI-polish Kimi shards dispatched against commit `735b13f` while a separate workflow shipped `be4cf3d` ("style: ui polish from previous run") on the same files — worktrees aged 13 commits stale, would have re-applied landed changes. Gate compares worktree HEAD vs `$CWD` HEAD; if drift touched any patch files → exit 7 + warning + `--force` override. Smoke-tested live: caught Shard C as 100% duplicate (auth.tsx + landing.tsx collision with `be4cf3d`); operator cancelled all stale shards and redispatched fresh against current main. Routing-lock taxonomy now explicit in §29.15 (per-shard / per-path / external-stream / cross-colony all distinct failure modes, each with own coverage). Coverage gap: same gate needs porting to gemini/grok/jules merge paths — deferred until n≥2 evidence on another lane. v2.15.0 (one turn earlier) shipped the queen-per-session architecture. §1.2 NEW: any model can queen; Claude-as-queen is a default, not a requirement. Workload-shape routes the orchestrator: **Claude for breadth + audit**, **Codex for depth (voice/realtime/single-SDK/UI-polish)**, **Jules for async overnight PR batches**. Symmetric §4.2 routing matrix — whichever queen runs, any other lane is dispatchable. New `~/.claude/scripts/claude-rescue.sh` (~30 lines) closes the loop: Codex-led sessions can call Claude back via `claude -p` for long-form planning / strategy / doc work. New `AGENTS.md` open-standard contract (co-stewarded by OpenAI/Anthropic/Google/Cursor/Factory) — repos carry both CLAUDE.md (Claude harness) and AGENTS.md (Codex/Jules harness), same source of truth. **Deliberately NOT shipped:** Codex hook port, state-harness migration, watcher daemon refactor, Codex-shaped 1,611-skill loader, mode-signature detector — all multi-week v3 work; until then, Codex/Jules are queens for depth/async only, not breadth. Evidence: n=2 (2026-05-11 voice + UI/UX both shipped via Codex standalone after failing under Claude+ceremony). v2.14.4 closed the per-shard fix (rule 3.5); v2.15.0 closes the per-session fix.).
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
