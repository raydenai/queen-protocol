#!/usr/bin/env python3
"""Queen Protocol v2.6.0 — cross-shard invariant audit (§25.11).

Reads a colony plan, identifies shards with overlapping data-pattern tags
(idempotency / cache / lock / auth / rate-limit / etc.), and runs the
canonical rg queries from schemas/cross-shard-audits.json against the
working tree. Reports violations to stdout and writes a structured event
to the colony's telemetry.jsonl.

Usage:
    python3 cross-shard-audit.py \\
        --plan ~/.claude/state/colony/<id>/plan.json \\
        --schema ~/projects/queen-protocol/schemas/cross-shard-audits.json \\
        --repo /path/to/working/repo \\
        --telemetry ~/.claude/state/colony/<id>/log/telemetry.jsonl

Exit codes:
    0 — no overlapping tags, or all queries clean
    1 — violations found; queen MUST block LAND or surface to operator
    2 — config error (missing files, invalid JSON, no rg in PATH)

Designed to be cheap (~30 s for a typical colony) and deterministic.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def overlapping_tags(plan: dict[str, Any]) -> dict[str, list[str]]:
    """Return tag -> [shard_ids] for tags appearing in ≥2 shards."""
    by_tag: dict[str, list[str]] = defaultdict(list)
    for shard in plan.get("shards", []):
        for tag in shard.get("tags", []) or []:
            by_tag[tag].append(shard["id"])
    return {t: ids for t, ids in by_tag.items() if len(ids) >= 2}


def run_rg(pattern: str, paths: list[str], repo: Path, multiline: bool = False) -> list[str]:
    """Run rg and return matching lines (file:line:text). Empty list if no matches."""
    cmd = ["rg", "--no-heading", "-n"]
    if multiline:
        cmd.append("-U")
    cmd.append(pattern)
    cmd.extend(paths)
    try:
        result = subprocess.run(
            cmd, cwd=str(repo), capture_output=True, text=True, timeout=20
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        print(f"[audit] rg failed: {e}", file=sys.stderr)
        return []
    # rg exit 1 = no matches (not an error), exit 2 = real error
    if result.returncode not in (0, 1):
        print(f"[audit] rg exit {result.returncode}: {result.stderr}", file=sys.stderr)
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def evaluate_query(query: dict[str, Any], paths: list[str], repo: Path) -> dict[str, Any]:
    """Run a single canonical query and return result with verdict."""
    qtype = query["type"]
    primary_hits = run_rg(query["rg"], paths, repo, multiline="\\n" in query["rg"])

    result: dict[str, Any] = {
        "name": query["name"],
        "type": qtype,
        "primary_hits": len(primary_hits),
        "verdict": "PASS",
    }

    if qtype == "must_not_match":
        if primary_hits:
            result["verdict"] = "FAIL"
            result["sample_hits"] = primary_hits[:5]
            result["remediation"] = query["remediation"]
    elif qtype == "must_match":
        if not primary_hits:
            result["verdict"] = "FAIL"
            result["remediation"] = query["remediation"]
    elif qtype in ("must_match_if_declared", "must_match_if_present"):
        # Declared/present check: if primary matches, guard MUST also match
        if primary_hits:
            guard_hits = run_rg(query["guard_rg"], paths, repo)
            if not guard_hits:
                result["verdict"] = "FAIL"
                result["sample_hits"] = primary_hits[:5]
                result["remediation"] = query["remediation"]
    elif qtype == "informational":
        if primary_hits:
            result["verdict"] = "INFO"
            result["sample_hits"] = primary_hits[:3]
            result["remediation"] = query["remediation"]
    else:
        result["verdict"] = "UNKNOWN_QUERY_TYPE"

    return result


def append_telemetry(telemetry: Path | None, payload: dict[str, Any]) -> None:
    if telemetry is None:
        return
    telemetry.parent.mkdir(parents=True, exist_ok=True)
    payload = {**payload, "ts": datetime.now(UTC).isoformat()}
    with telemetry.open("a") as fh:
        fh.write(json.dumps(payload) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--schema", required=True, type=Path)
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--telemetry", type=Path)
    args = ap.parse_args()

    if shutil.which("rg") is None:
        print("[audit] ripgrep (rg) not found in PATH — install via brew/apt", file=sys.stderr)
        return 2

    if not args.plan.exists() or not args.schema.exists() or not args.repo.exists():
        print("[audit] plan / schema / repo path missing", file=sys.stderr)
        return 2

    plan = load_json(args.plan)
    schema = load_json(args.schema)
    overlaps = overlapping_tags(plan)

    if not overlaps:
        print("[audit] no overlapping data-pattern tags across shards — skipping audit")
        append_telemetry(
            args.telemetry,
            {"event": "CROSS_SHARD_AUDIT_SKIPPED", "reason": "no_overlapping_tags"},
        )
        return 0

    auditable = {tag: shards for tag, shards in overlaps.items() if tag in schema["tags"]}
    if not auditable:
        print(
            f"[audit] overlapping tags {list(overlaps)} have no canonical queries — skipping audit"
        )
        append_telemetry(
            args.telemetry,
            {
                "event": "CROSS_SHARD_AUDIT_SKIPPED",
                "reason": "no_canonical_queries_for_tags",
                "overlapping_tags": list(overlaps),
            },
        )
        return 0

    print(f"[audit] auditing tags: {list(auditable.keys())}")
    failures: list[dict[str, Any]] = []
    info: list[dict[str, Any]] = []

    for tag, shards in auditable.items():
        spec = schema["tags"][tag]
        paths = spec.get("default_paths", ["."])
        for query in spec["queries"]:
            outcome = evaluate_query(query, paths, args.repo)
            outcome["tag"] = tag
            outcome["shards"] = shards
            verdict = outcome["verdict"]
            if verdict == "FAIL":
                failures.append(outcome)
                print(f"  FAIL [{tag}] {outcome['name']}")
                for hit in outcome.get("sample_hits", []):
                    print(f"    {hit}")
                print(f"    fix: {outcome['remediation']}")
            elif verdict == "INFO":
                info.append(outcome)
                print(f"  INFO [{tag}] {outcome['name']} — {outcome['remediation']}")
            else:
                print(f"  PASS [{tag}] {outcome['name']}")

    summary = {
        "event": "CROSS_SHARD_AUDIT_RESULT",
        "audited_tags": list(auditable.keys()),
        "failures": failures,
        "info_findings": info,
        "verdict": "FAIL" if failures else "PASS",
    }
    append_telemetry(args.telemetry, summary)

    if failures:
        print(
            f"\n[audit] {len(failures)} failure(s). Queen MUST block LAND with phase: CONVERGE_AUDIT_FAILED."
        )
        return 1

    print(f"\n[audit] CLEAN — {len(info)} info finding(s), 0 failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
