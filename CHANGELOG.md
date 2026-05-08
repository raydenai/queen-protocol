# Changelog

All notable changes to the Queen Protocol. Self-ratings are deliberately honest; review-grounded scores cite the reviewer.

## v2.3.1 — 2026-05-08

**Calibration release.** Three patches landed after the protocol's first three real-execution colonies:

- **§17.1** — `agent:general-purpose` cost row recalibrated to **$0.10–0.15/shard** from real-data observation across 3 dispatches. v2.3's $0.05 estimate was 2× low (diagnostic agents read many files; 70k–110k input tokens observed).
- **§3.1 step 4 audit-shard exception** — skill-grep gate is structurally unrunnable on read-only diagnostic shards (no diff/commits to grep). v2.3 would falsely DIRTY-reject any audit shard citing skills. v2.3.1 explicitly accepts `skills_loaded` as advisory metadata for `kind: "diagnostic"` shards.
- **§3.5 NEW audit-shard report variant** — codifies the `audit_findings` field structure used by diagnostic shards, parallel to §3.3 reviewer-ant variant.

**Self-rated:** ~8/10. Confidence increment is small but **earned** — protocol now has live data backing its cost projections.

## v2.3 — 2026-05-07

**Contraction + honesty release.** Applied surgically based on v2.2 review consensus.

**Bugs fixed (Codex review):**

- **§4.2 routing order** — branching check now precedes tournament check. v2.2 routed payment shards with `has_explicit_branches: true` to tournament instead of branching.
- **§4.2 type contract** — full type docstring for `route()` arguments (Gemini council finding).
- **§18.1 fencing token storage** — durable monotonic counter at `~/.claude/state/colony/fencing-counter` instead of `lock-acquired-at + counter` (which wasn't durable across queen restarts).

**Honesty added (Kimi + Perplexity council):**

- **§18.0 single-host vs multi-host scope** — explicit table marking which §18 invariants earn their cost on single-host vs `MULTI-HOST DEFERRED`.
- **§18.1 Kleppmann compliance boundary** — queen-side fencing catches stale REPORTS and stale MERGES but NOT stale SIDE EFFECTS on single-host. Single-host mitigation is via worktree containment + secrets boundary + idempotency keys.
- **§18.5 Lamport clocks → MULTI-HOST DEFERRED** — single-host needs only timestamps + transitions.log, not logical clocks.
- **§20.6 SLO measurement infrastructure** — table admitting which SRE capabilities are ENFORCED, NOT WRITTEN, NOT WIRED. Until runtime kernel ships, §20 SLO targets are hypotheses to test, not live controls.

**Self-rated:** ~7.5/10. Honesty was the upgrade.

## v2.2 — 2026-05-07

**Full-spectrum architectural rewrite.** Worker primitive becomes polymorphic — Claude Code child sessions are first-class workers (default for non-trivial work), with Kimi/Codex/Agent as backends in a hybrid routing matrix.

**Eight orchestration models added:**

- **Model C** — Hybrid routing per shard (§4)
- **Model K** — Specialist roles (§11): role-tuned claude-ants with skill bundles + pre-load files
- **Model Q** — Checkpoint gates (§2.2.5, §2.6.5): explicit human-approval pauses
- **Models L+M** — Tournament + Branching shards (§12): parallel exploration for high-stakes / uncertain decisions
- **Model R** — Honeycomb broker (§13): shared-interface coordination without senior-ant serialization
- **Models J+D** — Recursive + Hierarchical colonies (§14): scale past 12-shard ceiling
- **Model N** — Memory feed (§15): pre-PLAN retrieval + post-LAND harvest
- **Model T** — Continuous / scheduled colonies (§16): cron + event-driven

**Six Perplexity-council additions** (3-model review: GPT-5.5 Thinking + Claude Opus 4.7 Thinking + Gemini 3.1 Pro Thinking):

- **§3.4 Semantic injection defenses** (Opus 4.7's unique find)
- **§17 Cost model** with $10/$50/day budget thresholds
- **§18 Distsys invariants** (fencing, generation numbers, idempotency, sagas)
- **§19 Security model** with worktree-escape CVE anchors (CVE-2024-32002 — Gemini's unique find)
- **§20 SLOs + error budgets** (Google SRE)
- **§21 Durable execution + workflow versioning** (Temporal/DBOS-anchored)

**Reviewer scores:** Self-rated 9/10 (inflated; real ≈ 6/10). **Codex 7.3/10**, **Kimi 4.0/10** ("split into multiple docs"). The gap between description and enforcement was the overrating's source — fixed in v2.3 + v2.3.1.

## v2.1 — 2026-05-07

**Gap-closing release.** All issues from v2 reviews addressed:

- **Concurrent-queen lock** (§2.1) with stale detection
- **DAG pre-validation** (§2.2) with five mandatory checks
- **No-progress watchdog + cap exhaustion** (§2.4)
- **Integration worktree converge** (§2.6) with snapshot/rollback boundary
- **Verify references verify-done.sh** (§2.7) — single source of truth
- **Shard state machine** (§2.9) — explicit transition table
- **Hardened report contract** (§3) with six-step queen validation pipeline
- **active.json schema + atomic write + resume drill** (§8.1)
- **Telemetry sink** (§8.2)
- **Retention/GC policy** + disk-pressure circuit breaker (§8.3, §8.4)
- **Skill auto-verification by grep** (§9.1)

**Self-rated:** 8.5/10.

## v2 — initial kernel

**Persistent state, structured reports, reaper, critical-path serialization, backend selection matrix.**

**Reviewer scores:** Self-rated 7.5/10. **Codex 6.5/10**, **Kimi 5.0/10**.

Identified gaps that v2.1 addressed: state-machine leaks, active.json schema contradiction, DAG deadlock, merge rollback boundary, semantic conflicts, LLM-honesty assumption, two-queen split-brain, no telemetry.

## v1 — informal

"Describe the org chart." Phases existed but no failure handling, no persistence, no structured reports, no senior-ant priority. Self-rated 6.5/10.
