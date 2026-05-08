# Changelog

All notable changes to the Queen Protocol. Self-ratings are deliberately honest; review-grounded scores cite the reviewer.
## v2.4.0 — 2026-05-08

**Minor bump.** Two real-evidence patches:

- **§22.10 corrected** — meshboard's `colony_ops_producer` is a `fab team.broadcast` wrapper with a hardcoded node allowlist (`eagle`, `titan`, `nova`, `poseidon`, `dr_umit`), not a generic JSONL tailer. v2.3.2 was wrong. **Real integration ships in this release**: [`scripts/colony-meshboard-adapter.sh`](scripts/colony-meshboard-adapter.sh) — watches `~/.claude/state/colony/*/log/telemetry.jsonl`, maps shard ids to meshboard's bucket allowlist, POSTs events to `/api/colony/message`. Verified working: 71+ events flowed during Colony 7 dispatch.
- **§2.7 Tier-2 NEW — Auto-grep wiring gate.** Every new `run_*` agent factory function added in a colony's diff must have ≥1 caller outside its own file. Zero callers → DEAD CODE → wire-or-delete shard required before LAND. Closes the audit-found dead-code class (Colony 4 caught `run_ab_test_ideator` had zero callers).

**Why minor bump (not patch):** §22.10 was demonstrably wrong, and §2.7 is a new enforced control, not a calibration tweak. The README `Current version` line bumps to v2.4.

**Self-rated:** ~8.5/10. Same as v2.3.4. Rating doesn't move because no new architectural surface, just two findings landed honestly with a shipping adapter.

## v2.3.4 — 2026-05-08

**Schema enforcement + first max-mode dogfood calibration.** Three patches landed after Colony 4 (`2026-05-08-mesh-trio-bootstrap-and-test-backfill`) — 5 shards, 113 tests, 2 real bugs found, 15 min wall-clock, ~2.0× speedup vs default-mode baseline.

- **§3.1 Step 2 hardened** — explicit required-key allowlist, strict `status` enum (`DONE | FAILED | TIMEOUT` only), strict gate-object schema, reject-on-unknown-keys.
- **§3.6 NEW pre-submit validator** — [`scripts/validate-report.py`](scripts/validate-report.py) ships in this repo. Ant prompts MUST include the validation step; queen runs the same script at converge. Closes the Colony 4 finding where 3 of 4 ants invented divergent report shapes (`"PASS"` not `"DONE"`, `pytest_result` not `gates`, etc.).
- **§17.1 cost row split** — `agent:general-purpose (audit/diagnostic)` ~$0.10–0.15 vs `agent:general-purpose (write-shard)` ~$0.08–0.12. Calibrated from Colony 4's 4 parallel write ants.
- **§25.7 speedup calibrated** — projection 2.7× / actual 2.0× on a single colony. Schema-divergence overhead + first-run setup cost explain the gap. Updated projection: 2.5–3.0× sustained with §3.6 validator + warm setup.

**Real bugs surfaced by Colony 4 (would have shipped silently):**

- `abandoned_cart`: `_send_sequence_email` passes `template_name="abandoned_cart_1|2|3"` to `ResendClient` but only one `templates/abandoned_cart.py` exists. Live `RESEND_API_KEY` → `ModuleNotFoundError`.
- `conversion_auditor`: Layer 1/3/7 1.5× weighting + compliance→`BLOCK_PUBLISH` override are LLM-trusted, NOT server-enforced. Audit recommends server-side belt-and-suspenders in routes.

**Self-rated:** ~8.5/10. Confidence increment is real because §3.6 closes the only consistent failure mode observed in dogfood.

## v2.3.3 — 2026-05-08

**Max-Mode profile (now DEFAULT) — lightning-speed shipping.** Adds `plan.mode: "max-speed"` as the default colony profile when no `mode` field is specified.

- **§25 NEW** — Max-Mode profile section with full activation, override knobs, statistical claims, and per-shard escape semantics.
- **§25.1** — `max-speed` is now the **default** when `mode` is omitted; explicit `mode: "default"` to opt back into full-rigor.
- **§25.5** — Per-shard auto-promotion: `priority: critical` shards or shards touching production-path globs (`supabase/migrations/`, `stripe*`, `middleware.ts`, RLS, `.env.production*`) fall back to default-mode rules even inside max-speed colonies.

**What flips ON in max-mode:**

- Concurrency cap 6–12 → **24 parallel write-shards**
- Default backend `claude-ant` → **`kimi-isolated`** (~10× cheaper, ~10× more concurrent)
- Sub-queen auto-engage threshold 30 → **15 shards**
- Honeycomb broker auto-spawns when 3+ shards share a types path
- Heartbeat interval 60s → **30s**
- Telemetry writes buffered, flushed at phase transitions

**What flips OFF in max-mode:**

- §2.2.5 PLAN checkpoint default-skip (unless production paths)
- §3.1 step 5 gate-rerun: from "every gate" to **sample-rate (1 in N=3)**
- §2.7 Tier-2 dual review → **single review** (alternates kimi/codex per colony hash)
- §9.1 skill-grep verification: accept `skills_loaded` as advisory always
- §12 tournament/branching disabled by default

**Hard floors NEVER disabled (preserved in all modes):**

- §3.1 steps 1–3 (parse, schema, diff truth)
- §2.6 step 2 (files_allowed gate — conflict surface = 0)
- §3.4 (semantic injection defenses)
- §19 (security model — secrets boundary, worktree escape, supply chain)
- §10 (hard rules)
- §2.6.5 CONVERGE checkpoint when production paths touched

**Realistic speedup target:** 2.7× for 5-shard write-colonies, 5–7× for refactor sweeps with shared types, 8–10× for 20+ shard colonies via sub-queen auto-engage. To be calibrated from real metrics in subsequent colonies.

**Self-rated:** ~8/10 (same as v2.3.2). Rating doesn't move because architectural enforcement didn't change — max-mode is a performance profile flipping defaults, not a safety addition. Real validation comes from the first max-mode ConvertZap colony.

## v2.3.2 — 2026-05-08

**Companion-stack integration release.** Documents the [mesh-trio](https://github.com/umitkacar) (`meshterm` + `claude-mesh` + `meshboard`) as canonical companion infrastructure. Retires partially-obsolete "v3 deferred" claims that the upstream solved.

- **§22.10 NEW** — Companion stack section with installation + `colony_ops_producer` integration pattern for streaming `telemetry.jsonl` into the meshboard dashboard.
- **§20.6 measurement-infra table** — dashboard + alerting rows flipped from "NOT WRITTEN" / "NOT WIRED" to **"EXTERNAL via meshboard"** with config snippet.
- **§22.3 watch loop** — push-based heartbeats via claude-mesh signal subscription noted as the upgrade path from polling.
- **§14.2 sub-queens** — claude-mesh becomes the cross-host signaling substrate for top-queen ↔ sub-queens.
- **§24 v3 candidates** — dashboard + cross-session-signaling rows retired (mesh-trio shipped them); colony.sh runtime kernel + multi-host fencing + skill signature cache remain.

**No new architectural work** — just honest acknowledgment that upstream solved problems v2.3.1 deferred. The mesh-trio is observability + signaling infrastructure; it does not replace the queen-side state machine (lock + plan.json + active.json + report validation), which the protocol still owns end-to-end.

**Self-rated:** ~8/10. Same as v2.3.1; rating doesn't move because architectural enforcement didn't change — only the integration story.

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
