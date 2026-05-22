#!/usr/bin/env bash
# validate-shard-graph.sh — Queen Protocol v2.20.1 pre-dispatch shard graph validator
#
# Validates a shard graph JSON file BEFORE the super-queen dispatches child queens.
# Catches anti-decomposition rule violations (§30.3) at decomposition time,
# not at runtime collision.
#
# Usage:
#   validate-shard-graph.sh [--quiet] [--fix] <shard-graph.json>
#
# Exit codes:
#   0 — shard graph is valid (warnings may have been printed)
#   1 — at least one violation detected (structured stderr listing)

set -euo pipefail

QUIET=0
FIX=0
FILE=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --quiet) QUIET=1; shift ;;
    --fix)   FIX=1;   shift ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)  FILE="$1"; shift ;;
  esac
done

if [[ -z "$FILE" ]]; then
  echo "Usage: validate-shard-graph.sh [--quiet] [--fix] <shard-graph.json>" >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  if [[ $QUIET -eq 1 ]]; then
    echo "FILE NOT FOUND: $FILE" >&2
  else
    echo "File not found: $FILE" >&2
  fi
  exit 1
fi

# ── embedded python validator ─────────────────────────────────────────────────
python3 - "$FILE" "$QUIET" "$FIX" <<'PYEOF'
import json
import sys
from collections import defaultdict

FILE, QUIET_STR, FIX_STR = sys.argv[1:4]
QUIET = QUIET_STR == "1"
FIX = FIX_STR == "1"

# ── helpers ───────────────────────────────────────────────────────────────────

def err(msg):
    print(msg, file=sys.stderr)

def _norm_path(p):
    return p.rstrip("/")

def _glob_overlap(a, b):
    """True if two file globs/paths overlap (anti-decomposition rule §30.3)."""
    a = _norm_path(a)
    b = _norm_path(b)
    if a == b:
        return True
    # Directory prefix overlap
    if a.startswith(b + "/") or b.startswith(a + "/"):
        return True
    # Glob-style wildcard overlap (naive: if one contains the other)
    if "*" in a or "*" in b:
        # e.g. src/**/*.py vs src/auth.py  -> overlap
        # strip trailing wildcards and compare prefix
        a_base = a.split("*")[0].rstrip("/")
        b_base = b.split("*")[0].rstrip("/")
        if a_base == b_base:
            return True
        if a_base.startswith(b_base + "/") or b_base.startswith(a_base + "/"):
            return True
    return False

def _files_overlap(fa1, fa2):
    for a in fa1:
        for b in fa2:
            if _glob_overlap(a, b):
                return True
    return False

def _find_cycles(adj, nodes):
    """DFS cycle detection. Returns list of cycles (each cycle is a list of nodes)."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in nodes}
    cycles = []
    path = []

    def dfs(node):
        color[node] = GRAY
        path.append(node)
        for neighbor in adj.get(node, []):
            if neighbor not in color:
                continue  # unresolved — already reported elsewhere
            if color[neighbor] == GRAY:
                idx = path.index(neighbor)
                cycles.append(path[idx:] + [neighbor])
            elif color[neighbor] == WHITE:
                dfs(neighbor)
        path.pop()
        color[node] = BLACK

    for node in nodes:
        if color[node] == WHITE:
            dfs(node)
    return cycles

# ── validation core ───────────────────────────────────────────────────────────

def validate(data):
    violations = []
    warnings = []

    if not isinstance(data, dict):
        return ["Invalid JSON: top level must be an object"], []

    shards = data.get("shards")
    if not isinstance(shards, list):
        return ["Invalid JSON: 'shards' must be an array"], []

    # Required fields per §4 shard schema
    required = {"id", "tags", "kind", "priority", "complexity", "files_allowed", "depends_on"}
    valid_kinds = {"code", "review", "diagnostic"}
    valid_priorities = {"critical", "normal", "low"}
    valid_complexities = {"obvious", "mechanical", "complex"}

    shard_ids = set()
    id_to_shard = {}
    id_to_idx = {}

    # ── schema pass ──────────────────────────────────────────────────────────
    for idx, shard in enumerate(shards):
        prefix = f"shard[{idx}]"
        if not isinstance(shard, dict):
            violations.append(f"{prefix}: not a JSON object")
            continue

        missing = required - set(shard.keys())
        if missing:
            violations.append(f"SCHEMA: {prefix} missing required fields: {sorted(missing)}")

        sid = shard.get("id")
        if sid is not None:
            if not isinstance(sid, str) or not sid.strip():
                violations.append(f"SCHEMA: {prefix} 'id' must be a non-empty string")
            elif sid in shard_ids:
                violations.append(f"SCHEMA: duplicate shard id '{sid}'")
            else:
                shard_ids.add(sid)
                id_to_shard[sid] = shard
                id_to_idx[sid] = idx

        if "kind" in shard and shard["kind"] not in valid_kinds:
            violations.append(f"SCHEMA: {prefix} invalid kind '{shard['kind']}'")
        if "priority" in shard and shard["priority"] not in valid_priorities:
            violations.append(f"SCHEMA: {prefix} invalid priority '{shard['priority']}'")
        if "complexity" in shard and shard["complexity"] not in valid_complexities:
            violations.append(f"SCHEMA: {prefix} invalid complexity '{shard['complexity']}'")

        if "files_allowed" in shard:
            fa = shard["files_allowed"]
            if not isinstance(fa, list):
                violations.append(f"SCHEMA: {prefix} 'files_allowed' must be an array")
            elif len(fa) == 0:
                violations.append(f"SCHEMA: {prefix} 'files_allowed' must not be empty")
            else:
                for f in fa:
                    if not isinstance(f, str) or not f.strip():
                        violations.append(f"SCHEMA: {prefix} 'files_allowed' contains invalid entry")

        if "depends_on" in shard and not isinstance(shard["depends_on"], list):
            violations.append(f"SCHEMA: {prefix} 'depends_on' must be an array")
        if "tags" in shard and not isinstance(shard["tags"], list):
            violations.append(f"SCHEMA: {prefix} 'tags' must be an array")

    # ── anti-decomposition / overlap ─────────────────────────────────────────
    overlap_clusters = []
    n = len(shards)
    for i in range(n):
        si = shards[i]
        if not isinstance(si, dict):
            continue
        fa_i = si.get("files_allowed", [])
        if not isinstance(fa_i, list):
            continue
        for j in range(i + 1, n):
            sj = shards[j]
            if not isinstance(sj, dict):
                continue
            fa_j = sj.get("files_allowed", [])
            if not isinstance(fa_j, list):
                continue
            if _files_overlap(fa_i, fa_j):
                overlap_clusters.append((si.get("id", f"idx{i}"), sj.get("id", f"idx{j}"), fa_i, fa_j))

    for a, b, fa_a, fa_b in overlap_clusters:
        violations.append(
            f"ANTI-DECOMPOSITION (§30.3): shards '{a}' and '{b}' have overlapping files_allowed "
            f"({fa_a} vs {fa_b}) — must be merged into one shard group with sub-shards"
        )

    # ── dependency checks ────────────────────────────────────────────────────
    adj = defaultdict(list)
    for shard in shards:
        if not isinstance(shard, dict):
            continue
        sid = shard.get("id")
        if not sid:
            continue
        for dep in shard.get("depends_on", []):
            adj[sid].append(dep)
            if dep not in shard_ids:
                violations.append(f"DEP-UNRESOLVED: shard '{sid}' depends_on '{dep}' which does not exist")

    # Senior priority rule: critical shards cannot depend on non-critical shards
    for shard in shards:
        if not isinstance(shard, dict):
            continue
        sid = shard.get("id")
        if shard.get("priority") == "critical":
            for dep in shard.get("depends_on", []):
                dep_shard = id_to_shard.get(dep)
                if dep_shard and dep_shard.get("priority") != "critical":
                    violations.append(
                        f"DEP-SENIOR: critical shard '{sid}' must not depend on non-critical shard '{dep}' (§2.2 DAG rule 5)"
                    )

    # Cycle detection
    cycles = _find_cycles(adj, shard_ids)
    for cycle in cycles:
        violations.append(f"DEP-CYCLE: {' -> '.join(cycle)}")

    # ── tier validity (v2.18.0 thresholds) ───────────────────────────────────
    for shard in shards:
        if not isinstance(shard, dict):
            continue
        sid = shard.get("id", "?")
        fa = shard.get("files_allowed", [])
        if not isinstance(fa, list):
            continue
        file_count = len(fa)
        el = shard.get("estimated_lines")

        if el is None:
            warnings.append(f"TIER-UNKNOWN: shard '{sid}' missing 'estimated_lines' — cannot validate tier")
            continue
        if not isinstance(el, int) or el < 0:
            violations.append(f"TIER-INVALID: shard '{sid}' estimated_lines must be a non-negative integer")
            continue
        if file_count == 0:
            violations.append(f"TIER-INVALID: shard '{sid}' has no files_allowed")
            continue

        if el < 30 and file_count == 1:
            expected = "solo"
        elif (file_count == 1 and el >= 30) or file_count == 2:
            expected = "review"
        elif file_count >= 3:
            expected = "race"
        else:
            expected = None

        backend = shard.get("backend", "")
        if backend and expected:
            solo_backends = {"queen-direct", "kimi-isolated"}
            race_backends = {"tournament", "branching", "claude-ant", "specialist:"}
            if expected == "race" and backend in solo_backends:
                warnings.append(f"TIER-MISMATCH: shard '{sid}' expects race tier but backend is '{backend}'")
            elif expected == "solo" and any(rb in backend for rb in race_backends):
                warnings.append(f"TIER-MISMATCH: shard '{sid}' expects solo tier but backend is '{backend}'")

    # ── cap-awareness sanity ─────────────────────────────────────────────────
    backend_counts = defaultdict(int)
    for shard in shards:
        if not isinstance(shard, dict):
            continue
        b = shard.get("backend")
        if isinstance(b, str) and b.strip():
            backend_counts[b] += 1

    for backend, count in backend_counts.items():
        if count >= 5:
            warnings.append(
                f"CAP-RISK: {count} shards routed to backend '{backend}' — "
                f"daily cap exhaustion risk (§30.4 lever 8)"
            )

    return violations, warnings

# ── fix mode (auto-merge overlapping shards) ──────────────────────────────────

def apply_fix(data):
    shards = list(data.get("shards", []))
    n = len(shards)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[rx] = ry

    for i in range(n):
        for j in range(i + 1, n):
            si, sj = shards[i], shards[j]
            if not isinstance(si, dict) or not isinstance(sj, dict):
                continue
            fa_i = si.get("files_allowed", [])
            fa_j = sj.get("files_allowed", [])
            if isinstance(fa_i, list) and isinstance(fa_j, list) and _files_overlap(fa_i, fa_j):
                union(i, j)

    groups = defaultdict(list)
    for i in range(n):
        groups[find(i)].append(i)

    new_shards = []
    merged_any = False
    for indices in groups.values():
        if len(indices) == 1:
            new_shards.append(shards[indices[0]])
        else:
            merged_any = True
            members = [shards[i] for i in indices]
            new_shards.append(_merge_shards(members))

    # Remove dangling depends_on (references to merged-away ids)
    new_ids = {s["id"] for s in new_shards if isinstance(s, dict) and s.get("id")}
    for s in new_shards:
        if isinstance(s, dict) and "depends_on" in s:
            s["depends_on"] = [d for d in s["depends_on"] if d in new_ids]

    data["shards"] = new_shards
    return data, merged_any

def _merge_shards(members):
    ids = [m["id"] for m in members if isinstance(m, dict) and m.get("id")]
    merged = {"id": "+".join(ids)}

    titles = [m.get("title", m.get("id", "")) for m in members if isinstance(m, dict)]
    merged["title"] = "Merged: " + ", ".join(titles)

    # Union files_allowed
    files = set()
    for m in members:
        if isinstance(m, dict):
            for f in m.get("files_allowed", []):
                if isinstance(f, str):
                    files.add(f)
    merged["files_allowed"] = sorted(files)

    # Union tags
    tags = set()
    for m in members:
        if isinstance(m, dict):
            for t in m.get("tags", []):
                if isinstance(t, str):
                    tags.add(t)
    merged["tags"] = sorted(tags)

    # Max priority
    prio_order = {"critical": 3, "normal": 2, "low": 1}
    max_prio = "low"
    for m in members:
        if isinstance(m, dict):
            p = m.get("priority", "low")
            if prio_order.get(p, 0) > prio_order.get(max_prio, 0):
                max_prio = p
    merged["priority"] = max_prio

    # Max complexity
    comp_order = {"complex": 3, "mechanical": 2, "obvious": 1}
    max_comp = "obvious"
    for m in members:
        if isinstance(m, dict):
            c = m.get("complexity", "obvious")
            if comp_order.get(c, 0) > comp_order.get(max_comp, 0):
                max_comp = c
    merged["complexity"] = max_comp

    # Kind preference: code > review > diagnostic
    kinds = [m.get("kind") for m in members if isinstance(m, dict)]
    if "code" in kinds:
        merged["kind"] = "code"
    elif "review" in kinds:
        merged["kind"] = "review"
    else:
        merged["kind"] = "diagnostic"

    # External depends_on only
    internal = set(ids)
    deps = set()
    for m in members:
        if isinstance(m, dict):
            for d in m.get("depends_on", []):
                if d not in internal:
                    deps.add(d)
    merged["depends_on"] = sorted(deps)

    # Backend: prefer most expensive / capable heuristic
    backends = [m.get("backend", "") for m in members if isinstance(m, dict)]
    order = ["tournament", "branching", "specialist:", "claude-ant", "meshterm:", "agent:", "kimi-isolated", "queen-direct"]
    chosen = ""
    for pat in order:
        for b in backends:
            if pat in b:
                chosen = b
                break
        if chosen:
            break
    if chosen:
        merged["backend"] = chosen

    # Sum estimated_lines
    total = 0
    for m in members:
        if isinstance(m, dict):
            el = m.get("estimated_lines")
            if isinstance(el, int):
                total += el
    merged["estimated_lines"] = total

    return merged

# ── main ──────────────────────────────────────────────────────────────────────

def main():
    try:
        with open(FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        err(f"INVALID JSON: {e}")
        sys.exit(1)
    except OSError as e:
        err(f"Cannot read file: {e}")
        sys.exit(1)

    violations, warnings = validate(data)

    # ── fix pass ──
    fix_notice = None
    if FIX and any("ANTI-DECOMPOSITION" in v for v in violations):
        data, merged = apply_fix(data)
        if merged:
            new_violations, new_warnings = validate(data)
            # Keep non-overlap violations; note that we fixed
            remaining = [v for v in new_violations if "ANTI-DECOMPOSITION" not in v]
            if remaining:
                fix_notice = "FIX: merged overlapping shards; remaining issues below."
                violations = remaining
                warnings = new_warnings
            else:
                fix_notice = "FIX: merged overlapping shards into sub-shard groups. Re-validate passes."
                violations = []
                warnings = new_warnings

    # ── emit ──
    if not QUIET:
        if fix_notice:
            print(fix_notice)
        for w in warnings:
            err(f"WARN: {w}")
        for v in violations:
            err(f"VIOLATION: {v}")

    if violations:
        if QUIET:
            # SessionStart-friendly: silent on green, single line on red
            err(f"Shard graph invalid: {len(violations)} violation(s). Run without --quiet for details.")
        sys.exit(1)

    if not QUIET:
        print("VALID: shard graph passes all checks.")
    sys.exit(0)

if __name__ == "__main__":
    main()
PYEOF
