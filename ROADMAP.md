# Queen Protocol — Multi-Phase Roadmap

Living document. Phases groups roll forward as versions ship + slip. Last updated 2026-05-22 (v2.19.1).

The roadmap is the **execution plan** for the operator's articulated vision (v2.19.0 §30): one Claude Code chat as super-queen, decomposing feature requests, spawning N parallel child queens, aggregating results to a single stream. Max speed AND max quality AND resource-wise — all three on the same axis when matrix tier matches task complexity.

## Vision (target end-state)

```
User chat (single terminal or IDE)
    ↓
Super-queen (Claude Code, §30 role)
    ↓
DECOMPOSE feature → shard graph (auto, v2.20.0)
    ↓ ↓ ↓
Queen-A    Queen-B    Queen-C   (parallel, file-disjoint shard groups)
    ↓         ↓          ↓
Sidecars  Sidecars  Sidecars   (Kimi/Codex/Gemini/Grok-Build/Antigravity per matrix)
    ↓         ↓          ↓
SHARED CACHE (v2.21.0) → INTEGRATION GATE (v2.22.0) → UNIFIED REPORT (v2.23.0)
    ↓
User
```

Today (v2.19.0): super-queen role is spec'd but operator-discipline-driven. Roadmap turns each lever into shipped automation.

## Phase Group 1 — Foundation (SHIPPED)

| Version | Headline | Status |
|---|---|---|
| v2.18.0 | Speed-first matrix defaults (race 5→3 files; parallel review 1+) + Antigravity §29.19 parallel-queen lane | ✓ shipped 2026-05-22 |
| v2.19.0 | Super-queen role spec §30 (10 routing levers, 5 coordination axes, 6 anti-fixes) | ✓ shipped 2026-05-22 |

## Phase Group 2 — Speed implementation (v2.19.x)

Implementations of §30 levers 5 and 8. Both already drafted by Kimi background tasks in Wave A.

| Version | Deliverable | Effort | Depends on | Wave |
|---|---|---|---|---|
| **v2.19.1** | This doc + §31 reference. **PLUS** Wave A activation: dispatch Kimi background drafts for v2.19.x. | shipping now (docs) | v2.19.0 | A.1 |
| **v2.19.2** | Parallel verification gates (lever 5): `verify-done.sh` refactored to run ruff + tsc + Kimi-review + Codex-review concurrently. ~3-5× Stop-hook clear time. | 1 session integration | Kimi draft (Wave A, pid=94024) | A.2 |
| **v2.19.3** | Cap-aware autopilot (lever 8): `cap-autopilot.sh` reads daily-cap files + usage; substitutes lanes at >80% cap (Codex→Gemini, Kimi→Gemma 4). | 1 session integration | Kimi draft (Wave A, pid=94109) | A.3 |

**Parallelizable:** v2.19.2 and v2.19.3 ship in same wave (file-disjoint).

## Phase Group 3 — Decomposition automation (v2.20.x)

The super-queen's hardest job (auto-decomposing "build feature X" into a shard graph) becomes a script-assisted prompt-template, not pure operator-discipline.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v2.20.0** | Auto-decomposition — prompt templates that turn a feature request into a §4-shaped shard graph. Operator reviews + edits before dispatch. | 1 session | v2.19.0 §30 spec |
| **v2.20.1** | Shard graph validator — file-overlap detection (§30.3 anti-decomposition rule), dependency-cycle detection, `files_allowed` conflict check. CLI tool. | 1 session | v2.20.0 |
| **v2.20.2** | Speculative dispatch at PLAN (lever 6) — high-confidence sub-shards fire in parallel while plan finalizes; discard on plan-change. | 2 sessions | v2.20.0 + state-machine extension |

**Parallelizable:** v2.20.1 ‖ v2.20.2 after v2.20.0 lands.

## Phase Group 4 — Cross-queen coordination (v2.21.x)

Once multiple queens fire in parallel, they need shared infrastructure to avoid duplicating reads and to serialize at shared files.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v2.21.0** | Cross-queen shared read cache (lever 7) — super-queen-managed cache; child queens read-through. Target 40-60% hit rate. | 2 sessions | v2.20.0 |
| **v2.21.1** | Shared-file serialization detector — pre-dispatch `files_allowed` overlap analysis; auto-merge into one queen with sub-shards OR auto-serialize writes. | 1 session | v2.20.1 |
| **v2.21.2** | Cross-queen progress aggregation via meshboard — extends §29.8 colony-watcher daemon to consume N queen status streams + emit unified view. | 2 sessions | colony-watcher refactor |

**Parallelizable:** all three after Phase 3 wave-1 lands.

## Phase Group 5 — Colony-level verification (v2.22.x)

Cross-queen verification: a colony of merged shards needs ONE integration pass, not N redundant runs.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v2.22.0** | Colony-level integration verification gate (lever 10) — single integration test pass on merged result. Cost N→1, quality preserved. | 1 session | v2.21.0 + v2.21.1 |
| **v2.22.1** | Cross-queen verification reuse (lever 4) — if reviewer-A passed diff X and shard-B's diff ⊂ X, skip shard-B's review. | 1 session | v2.21.0 (cache infra) |
| **v2.22.2** | Stop-hook parallel gates (lever 11) — same gates run concurrently at Stop hook level (paired w/ v2.19.2). | 1 session | v2.19.2 |

**Parallelizable:** all three after Phase 4 lands.

## Phase Group 6 — Operational UX (v2.23.x)

What the operator actually sees.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v2.23.0** | Unified meshboard view — CLI dashboard: `[Queen-A: 2/5 shipped] [Queen-B: converging] [Queen-C: blocked on A's API contract]`. | 2 sessions | v2.21.2 |
| **v2.23.1** | Cost ceiling dashboard — per-feature + per-queen cost tracking + ceiling alerts. | 1 session | v2.19.3 |
| **v2.23.2** | Failure-replay tooling — rerun failed shards with auto sidecar swap. | 1 session | v2.22.x |

## Phase Group 7 — Multi-host (v3.0) — graduates from "single-host production-ish" to multi-host

The v3 graduation. Today a colony lives on one machine. v3 spans machines.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v3.0.0** | Multi-host fencing — distributed dispatch-lock (Redis or Postgres advisory locks). | 3+ sessions | All v2.x stable |
| **v3.0.1** | Cross-host sidecar pool sharing — Kimi/Codex dispatches load-balanced across machines. | 2 sessions | v3.0.0 |
| **v3.0.2** | Cross-host meshboard — `claude-mesh` integration matures from signaling to authoritative state. | 3 sessions | v3.0.1 |

## Phase Group 8 — Quality from learning (v3.1.x)

Retrospective-driven tuning. Requires real-colony evidence; can't ship before n≥10 production colonies feed telemetry.

| Version | Deliverable | Effort | Depends on |
|---|---|---|---|
| **v3.1.0** | Retrospective-driven matrix tuning — auto-adjust tier thresholds based on win/loss data. | 2 sessions | n≥10 production colonies |
| **v3.1.1** | Lane substitution learning — which lane wins which shard class (Kimi vs Codex vs Gemini for migration / UI / refactor / etc.). | 2 sessions | telemetry corpus |
| **v3.1.2** | Decomposition pattern library — proven shard graphs become templates the super-queen reuses. | 2 sessions | n≥5 successful super-queen colonies |

## Critical path + parallel ship strategy

**Sequential critical path (longest chain):**

```
v2.19.1 (docs) → v2.19.2 (parallel gates) → v2.20.0 (auto-decompose) →
v2.20.1 (validator) → v2.21.0 (cache) → v2.22.0 (integration gate) →
v2.23.0 (meshboard) → v3.0.0 (multi-host) → v3.1.0 (matrix tuning)
```

**Parallel-shippable waves via super-queen dogfood:**

| Wave | Versions | Sessions if sequential | Sessions if 3-queen parallel |
|---|---|---|---|
| A | v2.19.1 + v2.19.2 + v2.19.3 + (kick off v2.20.0 design) | 4 | 1 |
| B | v2.20.0 + v2.20.1 + v2.20.2 | 4 | 2 |
| C | v2.21.0 + v2.21.1 + v2.21.2 | 5 | 2 |
| D | v2.22.0 + v2.22.1 + v2.22.2 | 3 | 1 |
| E | v2.23.0 + v2.23.1 + v2.23.2 | 4 | 2 |
| F | v3.0.0 → v3.0.1 → v3.0.2 (sequential, hard deps) | 8 | 8 |
| G | v3.1.0 ‖ v3.1.1 ‖ v3.1.2 (parallel after F begins) | 6 | 2 |

**Total sequential:** ~34 sessions. **Total with super-queen parallel (3-queen waves):** ~18 sessions. Speedup ~1.9× — bounded by Phase 7's sequential dependencies.

## Cross-cutting concerns (not phase-specific)

- **Test corpus expansion** — `~/projects/queen-protocol/test-corpus/` per v2.11 commitment. Each phase adds 3+ fixture colonies for validation.
- **Documentation generation** — auto-update §X.Y references when section count changes. Currently hand-maintained; v2.20+ candidate.
- **New sidecar integration** — protocol exists for adding lanes (Gemini was v2.14.2, Grok v2.14.3, Antigravity v2.18.0). Future sidecars follow same pattern.
- **Antigravity headless monitoring** — if Google adds a headless API to Antigravity, §29.19 framing flips and we get a 9th headless sidecar. Watch upstream.
- **Cost telemetry** — across v2.19.x → v2.23.x, accumulating per-lane cost data to feed v3.1.x learning.

## Calibration loop (how versions get re-rated)

Each version self-rates X/10 at ship. Re-rate after the first 3 real colonies exercise the version's surface. The protocol's §29.X entries show this pattern: ship → use → re-rate → patch (e.g. v2.16.0 8/10 → 10/10 after v2.16.1 closed the dormant-code gap).

Each roadmap version ships with a numbered "what could re-rate this down" list so the next operator knows what to watch for.

## Wave A status (live)

- **Track 1 (Claude, in-turn):** this ROADMAP.md + §31 reference + v2.19.1 CHANGELOG/README/commit. SHIPPING.
- **Track 2 (Kimi background, pid=94024):** v2.19.2 parallel verification gates DRAFT to `/tmp/v2.19.2-draft.sh` + design doc. RUNNING.
- **Track 3 (Kimi background, pid=94109):** v2.19.3 cap-aware autopilot DRAFT to `/tmp/v2.19.3-draft.sh` + design doc. RUNNING.

Drafts NOT committed — operator integrates after review in v2.19.2 + v2.19.3 ship turns.

## Anti-fixes for the roadmap itself

1. **Do not promote the roadmap to "binding contract."** It's a plan, not a commitment. Real evidence from production colonies re-prioritizes ruthlessly. A version that gets demoted on n=3 real-use evidence is more valuable than the same version shipped to spec.
2. **Do not parallel-ship Phase 7 (multi-host).** Hard dependencies make speedup illusory; distributed-lock correctness needs sequential audit.
3. **Do not skip the Phase 5 (verification) layer to get to Phase 6 (UX) faster.** Operational UX without colony-level integration verification ships fast-and-broken.
4. **Do not let `ROADMAP.md` drift from CHANGELOG.md.** When a version ships, immediately mark Phase Group ✓ here. The cost of one-line maintenance prevents documentation-of-aspirations vs documentation-of-reality drift.
