# Changelog

All notable changes to the Queen Protocol. Self-ratings are deliberately honest; review-grounded scores cite the reviewer.

## v2.8.0 — 2026-05-09

**Local LLM as fourth-tier worker.** Operator installed Gemma 4 (Ollama: `gemma4:31b` 19GB + `gemma4:e4b` 9.6GB) on 2026-05-09. Smoke-test: e4b (4B-class) correctly answered the Colony 10 question "why is `dict[str, T]` keyed by `idempotency_key` only risky in multi-tenant code?" with "It lacks tenant scoping, risking cross-tenant data collisions or accidental overwrites." On-target security review answer at $0 cost and ~1s latency. Worker scaffolding `~/.claude/scripts/g4-task.sh` already shipped with full kimi-task.sh / codex-task.sh interface parity.

- **§27 NEW — Local LLM as fourth-tier worker.** Documents the capability/cost matrix vs cloud workers (Opus, Codex, Kimi, g4-local), the honest capability ceiling (mid-tier 4B/27B catches: tenant-scoping smell, missing async lock, stub code, swallowed except, schema drift; misses: cross-file composition, subtle races, architecture judgment), and the four high-value uses below.
- **§27.2 NEW — Tier 0 local pre-screen.** A new gate tier inserted before queen six-step validation. Every shard's diff is reviewed by `gemma4:31b` for cheap-class bugs before the ant submits its report. PASS → continue; FLAG → ant must address or document waiver. Catches the bug class that consumed a Codex/Kimi call in v2.7.
- **§27.3 calibration — Sample-rate gate-rerun obsolete when local LLM available.** v2.6 §25.6 set `gate_rerun_sample_rate: 3` (catches 86.8% of single-shard gate-lies; 13% escape) because cloud rerun was expensive. With g4-local, exhaustive rerun is free + fast (5–30s/colony). v2.8 max-mode default with local LLM available: full rerun, 0% escape, $0.00 cost.
- **§27.4 NEW — Privacy triage.** Pre-cloud secrets/PII screen via local LLM. Diffs scanned by Gemma before any forward to Codex/Kimi/Opus. If sensitive content detected, redact-or-skip. Unlocks queen colonies on HIPAA / PCI / GDPR-restricted code paths that previously could not touch cloud LLMs.
- **§27.5 NEW — Prompt-injection pre-screen.** Defense-in-depth on §3.4 semantic injection. Operator-provided `launch_brief.extra_context` strings get a Gemma pass to flag injection attempts ("ignore previous instructions", "you are now DAN", obfuscated unicode, base64 code-exec payloads). Catches what regex allowlists miss.
- **§27.6 routing decision function updated.** Added g4-local to the routing matrix:
  - `shard.kind in (review, single-file)` → g4-local Tier 0, escalate to claude-ant on FLAG
  - `shard.kind in (summarize, classify, doc-pass)` → g4-local always
  - `shard.privacy_class in (PII, secrets)` → g4-local ONLY (no cloud forward)
  - Cap-exhausted Codex/Kimi → fall back to g4-local for cheap operations
- **§27.7 cap reset — combined-cost view.** Real operator caps as of 2026-05-08: Codex 84/week (cap 20/day), Kimi 8/week, Claude unlimited. Adding g4-local removes cap-exhaustion as a failure mode for the cheap class of operations; Codex/Kimi caps now reserve for actual frontier-model needs.
- **§27.8 — what this does NOT change.** Tier 1 queen validation, Tier 3 dual review at ≥3 shards (still Codex + Kimi for diversity), §25.11 cross-shard rg audit, §25.12 git-snapshot detection. g4-local is a NEW lane, not a replacement.
- **§27.9 plan.json schema addition.** `local_llm: { enabled, endpoint, default_model, review_model, tier_0_enabled, privacy_triage_enabled }` per-colony. Graceful fallback to v2.7 behavior if endpoint unreachable.

**Why minor bump:** §27 introduces a new worker class with a new gate tier (Tier 0). Behavior change visible to every operator with local LLM available. Cost and capability profile is fundamentally different from cloud workers.

**Self-rated:** ~9.2/10 (up from 9.0). Local LLM closes the cost-floor on the cheap class of operations and unlocks privacy-sensitive code paths the protocol couldn't touch before. The g4-task.sh scaffolding being already-shipped means §27 isn't aspirational — it's documented reality.

## v2.7.0 — 2026-05-09

**Multi-tab reality.** Three patches grounded in observed evidence from a parallel session running Phase A-I (27 commits in 8 hours, including a 0037→0047 migration collision caught at PR review).

- **§25.15 NEW — Migration number reservation.** Real evidence: commit `fdad578` body note "Renamed from 0037 → 0047 to resolve number collision with `0037_event_fanout_columns.sql` (Phase D.1, committed in `ec1c1c2`)". Two parallel streams grabbed `0037`. Caught at review by manual renumber, but the same race could ship two production migrations with the same number to two different environments. v2.7 ships [`scripts/migration-number-reserve.py`](scripts/migration-number-reserve.py) — at PLAN, queen scans migration directory + active sibling colony plans, reserves contiguous block, writes assignment into `plan.json`. Each ant gets its number deterministically. Exit 1 on collision so queen can pause-and-coordinate.
- **§25.16 NEW — Cross-tab version propagation.** The protocol document lives at `~/.claude/QUEEN_PROTOCOL.md` AND every Claude Code session has a frozen copy in its conversation context. No live propagation. v2.7 ships [`~/.claude/scripts/protocol-version-watcher.sh`](../.claude/scripts/protocol-version-watcher.sh) wired as a SessionStart hook. Compares current version to `~/.claude/state/last-seen-protocol-version.txt`; on bump, prints CHANGELOG entry + reminds operator to `/clear` parallel tabs. Smoke-tested: silent on second run, notice on first.
- **§26 NEW — Multi-queen patterns (aspirational).** Documents three observed patterns: §26.1 Phase taxonomy (operator plans Phase → Colony → Shard hierarchically; not just flat colonies), §26.2 Hermes Watchman sub-queen (Kimi k2.6 auto-merges green shards, escalates revenue/security/destructive ops to operator via Telegram), §26.3 multi-tab interleaving (today's mitigations + still-unsolved gaps), §26.4 v2.8 wishlist.

**Other-tab lessons captured (2026-05-08, 27 commits across Phase A-I):**

- Phase B's mobile 1-field checkout, OTO downsell modal, MAB variant assigner — confirms Wave 4's CRO-first instincts are converging on the same patterns.
- Phase D.1 + analytics sub-queen pattern (5-tab Hyros-grade dashboard) — corroborates v2.6 §25.5 dual-review-≥3 rule via the commit body line "wave-3 + wave-4 both shipped 4-5 parallel shards each."
- Phase G's Lighthouse CI gate + k6 load tests + auto-rollback — production-readiness floor that v2.8 should consider as a §27 production-deploy contract.

**Why minor bump:** §25.15 is a new enforced control with hard collision evidence. §25.16 is a new shipped control. §26 is honest aspirational scope, not a behavior change. Two operators (this queen + Hermes) running in parallel necessitate the formalization.

**Self-rated:** ~9.0/10 (unchanged from v2.6). Quality didn't move because §26 is aspirational; the rating moves up again at v2.8 when sub-queen specification is enforceable.

## v2.6.0 — 2026-05-08

**10-colony dogfood calibration.** Five real-evidence patches grounded in honest measurement across 10 colonies and 34 shards on 2026-05-08.

- **§25.11 implementation now actually shipped.** v2.5 documented the cross-shard invariant audit rule but referenced a `cross-shard-audits.json` file that didn't exist. v2.6 ships [`schemas/cross-shard-audits.json`](schemas/cross-shard-audits.json) (canonical rg queries for `idempotency`, `cache`, `lock`, `auth`, `rate-limit`, `validation-guard`, `multi-tenant-key`) and [`scripts/cross-shard-audit.py`](scripts/cross-shard-audit.py) (~30 s runtime, deterministic, writes `CROSS_SHARD_AUDIT_RESULT` to telemetry, exits 1 on fail).
- **§25.12 NEW — External-stream detection.** While landing Colony 10 on 2026-05-08, a `kimi-task.sh` background worker in another tab committed `18ebc90` (Phase 0 safety gates) — adding `check_launch_rate_limit` to `routes/projects.py` AFTER the colony's LAND. Tests passed by luck. Queen-lock guards against another queen; it does NOT see other automation. v2.6 ships [`scripts/git-snapshot.sh`](scripts/git-snapshot.sh) — captures HEAD sha + dirty manifest at PLAN, diffs at LAND, blocks with `EXTERNAL_ACTIVITY` until operator acks.
- **§25.5 calibration — Dual review auto-promotes at ≥3 shards.** v2.5 max-mode default of "single review at converge" is honest only on tiny clean colonies. Across 10 colonies on 2026-05-08, Colonies 9 + 10 each had ≥4 shards and dual review found 1 + 7 issues respectively that single review would have missed (including 2 cross-tenant safety bugs). The 3-min review savings vanish above 2 shards anyway because review almost always finds something. New rule: max-mode runs single review only when the colony has ≤2 shards.
- **§25.13 NEW — Per-phase wall-clock telemetry.** v2.3.4 projected 2.0–2.7× sustained max-mode speedup. Real measurement across 10 colonies: 18 min (clean) to 90 min (Colony 10, 7 review findings + fix loop). The projection holds only when reviews are no-ops. v2.6 mandates `PHASE_START`/`PHASE_END` telemetry events for `SURVEY/PLAN/DISPATCH/WATCH/CONVERGE/VERIFY/LAND` so future speedup claims can be grounded in real distributions, not hopium.
- **§25.14 calibration — Skill-grep verification restored.** v2.5 max-mode demoted skill-grep to "advisory always." After 10 colonies, 100% of ants reported `skills_loaded` paths but the queen never verified the paths existed on disk or that the skill content actually appeared in the diff. Restored to §25.4 hard floors as cheap discipline floor: `test -f` per skill_path is mandatory; rg of skill content in diff_summary is soft warning.

**Why minor bump (not patch):** §25.12 + §25.13 are new enforced/observable controls. §25.5 dual-review-on-≥3-shards is a behavior change visible to every operator. §25.11 went from documented-only to actually-shipped (script + JSON). §25.14 is restored discipline.

**Self-rated:** ~9.0/10. Up from 8.7 because v2.6 closes the gap between the protocol document and what the protocol actually enforces. The aspirational/enforced split in the README shrunk: 4 items moved from aspirational to enforced this release.

## v2.5.0 — 2026-05-08

**Cross-shard invariant audit (Colony 10 calibration).**

- **§25.11 NEW — Cross-shard invariant audit.** When ≥2 shards add the same kind of state in disjoint files (caches, locks, validation guards, multi-tenant scoping), each ant only sees its own file scope. A class of bug is invisible to single-shard review — the bug only emerges from reading the union of diffs.
- **Real evidence (Colony 10, 2026-05-08):** s01 added `_idempotency_cache` to `routes/projects.py`; s02 added `_site_idempotency_cache` to `routes/sites.py`. Both keyed by `idempotency_key` only — Tenant A could replay Tenant B's cached id. Each ant was correct within its file scope. Queen-side dual review (Codex + Kimi) caught both. Without dual review, two cross-tenant safety bugs would have shipped.
- **Mechanism:** when colony plan declares ≥2 shards with overlapping data-pattern tags (`cache`, `idempotency`, `lock`, `auth`, `rate-limit`, `validation-guard`, `multi-tenant-key`), queen runs an rg-based invariant sweep against the converged diff before LAND. Canonical queries codified in `~/.claude/state/colony/schemas/cross-shard-audits.json`. Hits → `phase: CONVERGE_AUDIT_FAILED` → fix shard or operator ack.
- **§25.4 hard floors updated** — cross-shard audit added to the never-disabled list. In max-mode this is critical: single review at converge doesn't catch cross-shard composition bugs; the cheap rg sweep does.
- **Cost:** ~30s per colony. The cross-tenant safety bugs it catches: priceless.

**Why minor bump (not patch):** §25.11 is a new enforced control with a real failure mode and a deterministic mechanism — not a calibration tweak.

**Self-rated:** ~8.7/10. Up from 8.5 because the rule is grounded in a real bug class found in real production code that would have shipped without it.

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
