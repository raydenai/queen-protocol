# Decompose Design Rationale (v2.20.0)

## Why templates over raw LLM reasoning

Today (v2.19.0), the super-queen decomposes feature requests via **in-context reasoning**: the operator asks for a feature, and the super-queen reasons ad-hoc about file trees, dependencies, and shard boundaries. This works, but it has three failure modes that v2.20.0 closes with reusable prompt templates.

---

## 1. Reproducibility

**Problem:** Two super-queen sessions given the same feature description produce different shard graphs. One session splits auth into 2 shards; another splits it into 4. One routes the payment shard to `claude-ant`; another routes it to `kimi-isolated`. The differences are not evidence-based — they are context-window noise.

**Template fix:** The `decompose-feature.md`, `decompose-bug.md`, and `decompose-refactor.md` templates encode a **deterministic decision tree** (§4.2 routing function, §5 tier thresholds, §30.3 heuristics). Given the same input + same codebase context, the template produces the same structural output. Randomness is confined to `estimated_lines` and `assumptions`, not shard topology.

**Evidence needed:** After 5+ real colonies using these templates, diff the emitted shard graphs for identical inputs. Target: >90% structural reproducibility (same `id` count, same `depends_on` edges, same `backend` assignments).

---

## 2. Calibration

**Problem:** Raw LLM reasoning drifts with model updates and context pressure. A super-queen that correctly decomposed "auth flow" last week may over-decompose it this week because the model's training distribution shifted, or because the context window was 40% full of prior conversation. There is no knob to turn.

**Template fix:** Templates expose explicit **calibration levers**:

- `routing_tier` thresholds (<30 LOC = solo; 1 file >30 LOC or 2 files = review; 3+ files = race) — adjustable in one place.
- `complexity` classification rules — `obvious` vs `mechanical` vs `complex` have concrete signals.
- `priority` assignment — `critical` is reserved for migrations + shared types + API contracts.
- Cost-mix target (60% free / 30% mid / 10% premium) — a budget policy, not a vibe.

When telemetry shows `shard_merge_no_retry_rate` dropping, the operator adjusts the template (e.g., raise the tournament threshold from `auth|payment` to `auth|payment|security-critical|migration`) rather than re-deriving the heuristic from first principles every session.

---

## 3. Debug-ability

**Problem:** When a colony fails because two shards had overlapping `files_allowed`, the post-mortem asks "why did the super-queen think they were disjoint?" With raw reasoning, the answer is "it seemed right at the time" — uninspectable.

**Template fix:** Templates require the decomposer to emit `dag_validation`:

```json
"dag_validation": {
  "acyclic": true,
  "all_deps_resolve": true,
  "files_overlap": false,
  "has_starting_shard": true
}
```

If `files_overlap` is `false` but converge finds a conflict, the bug is in the overlap-detection logic — a concrete, unit-testable function. If `all_deps_resolve` is `true` but a shard blocks forever, the bug is in the `depends_on` resolution — again, concrete.

Templates also require an `assumptions` array. When a colony fails because an assumption was wrong (e.g., "assumed OAuth2 Authorization Code flow" but user wanted magic links), the failure mode is **attributed to a specific assumption**, not to vague "model error."

---

## 4. Operator review gate (§2.2.5)

Templates are **guides for an LLM, not declarative state machines**. The super-queen emits a plan, but the operator reviews + edits before dispatch. The template makes this review efficient:

- **Standard schema** — operator knows where to look for `files_allowed`, `depends_on`, `backend`.
- **Assumptions surfaced** — operator spots bad assumptions in 5 seconds instead of reading 500 tokens of reasoning.
- **Validation block** — operator trusts the structural checks (acyclic, no overlap) and focuses on semantic judgment ("does shard 3 really need to block on shard 1?").

Without templates, operator review requires reverse-engineering the super-queen's ad-hoc reasoning. With templates, review is a checklist.

---

## 5. What templates are NOT

1. **Not a runtime kernel.** The templates do not dispatch, watch, converge, or verify. They produce `plan.json`. The existing §2 lifecycle executes it.
2. **Not a replacement for queen judgment.** The super-queen still decides whether to approve, redirect, or abort at the §2.2.5 checkpoint. The template is a draft, not a decree.
3. **Not a deterministic compiler.** LLM stochasticity remains in `estimated_lines`, `assumptions`, and tag selection. The template narrows the variance, it does not eliminate it.
4. **Not multi-host aware.** v2.20.0 templates are for single-host super-queens. Multi-host decomposition (v3.0) will extend these templates with host-affinity and latency-aware sharding.

---

## 6. Success criteria for v2.20.0

| Metric | Target | Measurement |
|---|---|---|
| Structural reproducibility (same input → same shard count + deps) | ≥ 90% | Diff 5 colonies on identical inputs |
| Operator edit count at PLAN checkpoint | ≤ 2 edits per plan | Count user corrections before APPROVE |
| Plan rejection rate (dag_validation fail) | ≤ 5% | Telemetry from `telemetry.jsonl` |
| Assumption accuracy (no bad assumptions in shipped colonies) | ≥ 80% | Post-LAND review: were assumptions valid? |
| Time-to-plan (feature request → plan.json emitted) | ≤ 60s | Wall-clock from user prompt to checkpoint |

These metrics feed into v3.1.2 (decomposition pattern library): successful template outputs become reusable patterns.

---

## 7. Relation to other roadmap items

- **v2.20.1** (shard graph validator) — hardens the `dag_validation` block into a CLI tool. The template emits assertions; the validator proves them.
- **v2.20.2** (speculative dispatch) — uses the template's high-confidence sub-shards to fire early while the plan finalizes. The template's `routing_tier` and `backend` fields tell the super-queen which shards are safe to speculate.
- **v2.21.0** (cross-queen shared read cache) — the template's `files_allowed` declarations are the cache-key schema. Disjoint files → cacheable reads; shared files → cache invalidation on write.
- **v3.1.2** (decomposition pattern library) — proven template outputs (e.g., the auth example in `decompose-examples.json`) become reusable macros. The super-queen matches "build user auth..." against the macro and pre-fills the shard graph.
