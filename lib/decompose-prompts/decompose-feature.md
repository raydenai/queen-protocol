# Decompose Feature — Meta-Prompt Template (v2.20.0)

> **Role:** Super-Queen auto-decomposer  
> **Input:** A user feature request (free text, e.g. "build user auth with email + Google OAuth + JWT sessions")  
> **Output:** A shard graph in JSON matching §4 schema, ready for operator review + edit before dispatch.

---

## 1. Input ingestion

Read the user's feature description. Classify into one of:

- **Feature list:** "build A + B + C"
- **Feature-with-constraints:** "build X, must integrate with existing Y, ship by Thursday"
- **Vague directive:** "make the app production-ready" → STOP. Refuse to expand without operator-approved scope (§30.2).

If vague: emit `{"status": "REFUSED", "reason": "scope insufficient", "requested_clarification": [...]}` and halt.

---

## 2. File-tree survey (heuristic, not exhaustive)

Before sharding, reason about the codebase surface:

1. **Disjoint file trees?**  
   Example: `apps/auth/` vs `apps/billing/` → separate shard groups, parallel queens.

2. **Shared files?**  
   Example: both features touch `package.json`, `src/types.ts`, `supabase/migrations/`, or `.env.example` → SAME queen, sub-shards, serialized at shared files.

3. **Cross-feature API contracts?**  
   Example: feature B consumes an endpoint that feature A creates → `depends_on` edge from B to A.

4. **Schema migrations?**  
   Any feature touching `supabase/migrations/` or `db/migrate/` → senior shard (priority: critical), runs alone, all others block on it (§6).

5. **Shared types / Pydantic schemas / OpenAPI contract?**  
   Same rule as migrations: senior shard, critical priority.

---

## 3. Decomposition heuristics

Apply these rules in order. The output is a **shard graph** (DAG).

| Signal | Action |
|---|---|
| Subsystems touch disjoint file trees | Separate top-level shard groups; can run under parallel queens |
| Subsystems share files OR package dependencies | Merge into one shard group; use sub-shards serialized at shared files |
| One subsystem produces an API contract another consumes | `depends_on` edge; consumer blocks on producer |
| Work includes DB schema migration | Single senior shard (priority: critical) for migrations + shared types |
| Work is purely additive (new files, no edits to existing shared files) | Higher parallelism; fewer `depends_on` edges |
| Work touches auth, payment, security-critical paths | Tag for tournament routing (§4.2 rule 3) |

**Anti-decomposition rule (HARD):**  
If two proposed shards have overlapping `files_allowed` globs, MERGE them into one shard. If the merged shard is too large, split it into **sub-shards** that still respect the overlap boundary (e.g., one queen handles `packages/types/` senior-first, then dispatches child shards for the disjoint consumers). Cross-queen file conflicts are the #1 multi-queen failure mode (§30.3, §30.7).

**Practical ceiling:** ~6–12 parallel shards per colony. Beyond that, sharding is contrived (§2.2).

---

## 4. §4 schema per shard

Every shard in the output graph must carry these fields:

```json
{
  "id": "s01",
  "title": "human-readable one-liner",
  "kind": "code | review | diagnostic",
  "tags": ["auth", "migration", "ui-polish", "mechanical", ...],
  "priority": "critical | normal | low",
  "complexity": "obvious | mechanical | complex",
  "files_allowed": ["glob/pattern/**"],
  "depends_on": ["s00"],
  "estimated_lines": 120,
  "skills_required": [".claude/skills/..."],
  "gates": ["typecheck", "pytest ..."],
  "deadline_minutes": 30
}
```

**Field derivation guidance:**

- `id` — sequential `s01`, `s02`, ... within the colony. Prefix with feature code if multi-feature colony (`auth-s01`).
- `tags` — drive routing in §4.2. Include domain tags (`auth`, `payment`, `stripe`), mechanism tags (`migration`, `codemod`, `rename`), and routing-hint tags (`ui-polish`, `single-screen`, `voice`, `realtime`, `openai-sdk`, `mechanical`, `test-backfill`).
- `priority` — `critical` for senior shards (migrations, shared types, API contracts). Everything else: `normal` unless explicitly low-priority polish.
- `complexity` — `obvious` if <30 LOC and pattern is known; `mechanical` if repetitive/codemod-shaped; `complex` if novel design or multi-file coordination.
- `files_allowed` — glob list. MUST NOT overlap with another shard's `files_allowed` in the same plan. If overlap is unavoidable, merge shards.
- `depends_on` — list of `id`s. Graph must be acyclic (`tsort` clean). At least one shard must have empty `depends_on`.
- `estimated_lines` — rough LOC guess. Drives tier decision below.

---

## 5. Routing tier decision (v2.18.0 thresholds)

Per shard, assign a dispatch tier:

| Tier | Threshold | Routing implication |
|---|---|---|
| **Solo** | `estimated_lines < 30` AND `files_allowed` covers exactly 1 file | Queen-direct or single cheap ant. No race, no review pair. |
| **Review** | 1 file >30 LOC OR 2 files total | Single ant + parallel dual review at converge (`kimi-rescue` + `codex-rescue`). |
| **Race** | 3+ files OR `priority: critical` OR tags include `auth`, `payment`, `security-critical` | Tournament or branching (§12). Default tournament = 3 backends racing on same shard. |

Apply the tier at PLAN time; it feeds into `backend` selection below.

---

## 6. Lane assignment per shard

Map each shard to its optimal backend using the §4.2 routing function, summarized here for template use:

```text
IF tags & {voice, realtime, openai-sdk, single-sdk-chain, ui-polish, frontend-taste, single-screen}
   OR kind == "stack-trace-fix"
   → agent:codex-rescue  (GPT-5.5 training distribution dominates)

IF tags & {async-pr, dep-bump, test-backfill, mechanical-mass-refactor}
   → jules-async  (fire-and-forget PR mode)

IF priority == critical
   → claude-ant  (or specialist match)  (full Opus reasoning, runs alone)

IF specialist match from registry (§11.3)
   → specialist:<role>

IF kind == review
   → [agent:codex-rescue, agent:kimi-rescue]  (parallel, single-message)

IF kind == diagnostic
   → agent:codex-rescue  (foreground, read-heavy)

IF complexity == mechanical OR tags & {codemod, rename, format}
   → kimi-isolated  (cheap one-shot)

IF idle meshterm pane in correct cwd
   → meshterm:<uuid>  (saves 30-60s spawn)

DEFAULT
   → claude-ant
```

**Cost discipline (§30.4 lever 2):** target mix 60% free/cheap (Kimi, Gemma 4, Gemini Flash) / 30% mid (Codex) / 10% premium (Claude-ant). Prefer `kimi-isolated` for mechanical shards; reserve `claude-ant` for critical-path or complex-design shards.

---

## 7. Anti-patterns to reject during decomposition

1. **Two shards touching `package.json` independently** → merge or serialize. `package.json` is a shared file.
2. **Frontend shard dispatched before API contract shard is DONE** → add `depends_on` edge.
3. **Migration lumped into a feature shard** → extract as senior `priority: critical` shard.
4. **Over-splitting** → if a shard is <15 LOC and obvious, absorb it into an adjacent shard or mark `queen-direct`.
5. **Under-splitting** → if a shard is >300 LOC or touches >6 files, consider sub-queen recursion (§14) or sub-shards.

---

## 8. Output format

Emit **only** the JSON below. No markdown wrapping. No conversational filler.

```json
{
  "schema_version": "2.20.0",
  "colony_id": "<auto-generated: YYYY-MM-DD-feature-name>",
  "goal": "<one-line feature summary>",
  "decomposition_type": "feature",
  "status": "PLAN",
  "shards": [
    {
      "id": "s01",
      "title": "...",
      "kind": "code",
      "tags": [...],
      "priority": "critical | normal | low",
      "complexity": "obvious | mechanical | complex",
      "files_allowed": ["glob/**"],
      "depends_on": [],
      "estimated_lines": 120,
      "skills_required": ["..."],
      "gates": ["..."],
      "deadline_minutes": 30,
      "routing_tier": "solo | review | race",
      "backend": "kimi-isolated | claude-ant | agent:codex-rescue | ..."
    }
  ],
  "dag_validation": {
    "acyclic": true,
    "all_deps_resolve": true,
    "files_overlap": false,
    "has_starting_shard": true
  },
  "assumptions": ["..."]
}
```

**dag_validation** — the decomposer must assert these four booleans. If any is `false`, the plan is internally rejected; fix and re-emit.

**assumptions** — list every guess made because the feature description was ambiguous. Operator reviews these at the §2.2.5 checkpoint.

---

## 9. Template self-check before emitting

- [ ] Every `depends_on` resolves to an `id` in `shards`.
- [ ] No two `files_allowed` globs intersect.
- [ ] At least one shard has `depends_on == []`.
- [ ] Senior shards (`priority: critical`) do NOT depend on non-senior shards.
- [ ] `routing_tier` matches v2.18.0 thresholds.
- [ ] `backend` selection follows §4.2 order.
- [ ] Vague directives were refused, not hallucinated into scope.
