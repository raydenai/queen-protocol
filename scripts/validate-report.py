#!/usr/bin/env python3
"""Queen Protocol v2.10.2 report validator.

Usage:
    python3 ~/projects/queen-protocol/scripts/validate-report.py <path-to-report.json>
    python3 ~/projects/queen-protocol/scripts/validate-report.py --strict <path>

Exit codes:
    0 — report is valid (after alias normalization)
    1 — schema violations (errors printed to stderr)
    2 — JSON parse failure

v2.10.2 calibration (Elev-W1 colony evidence): real-world ants emit
identical-meaning fields under different names (`files_changed` for
`files_touched`, `completed_at` for `finished_at`, `done` for `DONE`,
etc.). Strict rejection produced 0/22-passing reports while the work
itself was sound.

The validator now:
  - Aliases known field-name variants to canonical names before checking
  - Normalizes status case (`done` → `DONE`)
  - Allows `started_at`/`finished_at`/`duration_seconds` to be derived
    from `timestamp`/`completed_at`/`wall_minutes` if present
  - Allows a wider ALLOWED_EXTRAS set for annotation slots seen in field

Use `--strict` to disable alias normalization (the v2.3.4 behavior).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED = {
    "schema_version",
    "shard_id",
    "attempt_id",
    "status",
    "started_at",
    "finished_at",
    "files_touched",
    "files_outside_allowed",
    "skills_loaded",
    "gates",
    "tests_added",
    "diff_summary",
    "conflicts_with",
    "assumptions",
    "next_steps_for_queen",
    "duration_seconds",
    "ant_kind",
}

# v2.10.2: alias map from observed real-world variants to canonical key
# Multiple aliases can map to the same canonical; we coalesce.
FIELD_ALIASES: dict[str, str] = {
    "files_changed": "files_touched",
    "files_modified": "files_touched",
    "files_created": "files_touched",
    "completed_at": "finished_at",
    "timestamp": "finished_at",
    "shard": "shard_id",
    "title": "diff_summary",
    "goal": "diff_summary",
    "notes": "diff_summary",
    "acceptance_gates": "gates",
    "phase": "ant_kind",
    "cap": "shard_id",
}

ALLOWED_EXTRAS = {
    "audit_findings", "findings", "verdict", "mode", "extra",
    "queen_notes", "operator_notes",
    # v2.10.2: Elev-W1 ants in production added these as legitimate slots
    "artifacts", "blocks_delivered", "critical_rules_verified",
    "migration", "wall_minutes", "files_outside_allowed_but_dropped",
}

VALID_STATUS = {"DONE", "FAILED", "TIMEOUT"}
STATUS_ALIASES = {
    "done": "DONE",
    "complete": "DONE",
    "completed": "DONE",
    "success": "DONE",
    "succeeded": "DONE",
    "fail": "FAILED",
    "failed": "FAILED",
    "error": "FAILED",
    "timeout": "TIMEOUT",
    "timed_out": "TIMEOUT",
}
VALID_GATE_STATUS = {"PASS", "FAIL", "SKIP"}
GATE_STATUS_ALIASES = {
    "pass": "PASS", "passed": "PASS", "ok": "PASS", "green": "PASS",
    "fail": "FAIL", "failed": "FAIL", "error": "FAIL", "red": "FAIL",
    "skip": "SKIP", "skipped": "SKIP", "n/a": "SKIP", "na": "SKIP",
}


def normalize(report: dict[str, Any]) -> dict[str, Any]:
    """Apply v2.10.2 alias normalization. Returns a new dict; original unchanged."""
    out = dict(report)

    # 1. Field-name aliases — canonical key wins; alias only used if canonical missing
    for alias, canonical in FIELD_ALIASES.items():
        if alias in out and canonical not in out:
            out[canonical] = out.pop(alias)
        elif alias in out and canonical in out:
            # Both present: drop the alias to canonicalize keyspace
            out.pop(alias)

    # 2. Status case-insensitive
    status = out.get("status")
    if isinstance(status, str):
        s_lower = status.strip().lower()
        if status not in VALID_STATUS and s_lower in STATUS_ALIASES:
            out["status"] = STATUS_ALIASES[s_lower]

    # 3. Derive timing fields if they're missing but related fields exist
    if "duration_seconds" not in out and "wall_minutes" in out:
        try:
            out["duration_seconds"] = int(float(out["wall_minutes"]) * 60)
        except (TypeError, ValueError):
            pass

    # 4. Gate-status case-insensitive
    if isinstance(out.get("gates"), list):
        for g in out["gates"]:
            if not isinstance(g, dict):
                continue
            gs = g.get("status")
            if isinstance(gs, str) and gs not in VALID_GATE_STATUS:
                gl = gs.strip().lower()
                if gl in GATE_STATUS_ALIASES:
                    g["status"] = GATE_STATUS_ALIASES[gl]

    return out


def validate(path: Path, strict: bool = False) -> list[str]:
    """Return list of error messages. Empty list = valid."""
    errors: list[str] = []

    try:
        report = json.loads(path.read_text())
    except FileNotFoundError:
        return [f"file not found: {path}"]
    except json.JSONDecodeError as e:
        return [f"PARSE FAIL: {e}"]

    if not isinstance(report, dict):
        return ["report must be a JSON object at top level"]

    if not strict:
        report = normalize(report)

    missing = REQUIRED - set(report.keys())
    unknown = set(report.keys()) - REQUIRED - ALLOWED_EXTRAS
    if missing:
        errors.append(f"missing required keys: {sorted(missing)}")
    if unknown:
        errors.append(
            f"unknown keys (must be in REQUIRED or ALLOWED_EXTRAS): {sorted(unknown)}"
        )

    status = report.get("status")
    if status not in VALID_STATUS:
        errors.append(f"status must be one of {sorted(VALID_STATUS)}; got '{status}'")

    gates = report.get("gates", [])
    if not isinstance(gates, list):
        errors.append("gates must be a list")
    else:
        gate_required = {"name", "command", "status", "output_tail", "duration_ms"}
        for i, gate in enumerate(gates):
            if not isinstance(gate, dict):
                errors.append(f"gates[{i}] must be an object")
                continue
            gmiss = gate_required - set(gate.keys())
            if gmiss:
                errors.append(f"gates[{i}] missing keys: {sorted(gmiss)}")
            gstatus = gate.get("status")
            if gstatus not in VALID_GATE_STATUS:
                errors.append(
                    f"gates[{i}].status invalid: '{gstatus}' "
                    f"(must be one of {sorted(VALID_GATE_STATUS)})"
                )

    started = report.get("started_at", "")
    finished = report.get("finished_at", "")
    if started and finished and finished < started:
        errors.append(
            f"finished_at ({finished}) must be >= started_at ({started})"
        )

    for arr_field in (
        "files_touched",
        "files_outside_allowed",
        "skills_loaded",
        "tests_added",
        "conflicts_with",
        "assumptions",
        "next_steps_for_queen",
    ):
        val = report.get(arr_field)
        if val is not None and not isinstance(val, list):
            errors.append(f"{arr_field} must be a list (got {type(val).__name__})")

    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", type=Path)
    ap.add_argument("--strict", action="store_true",
                    help="Disable v2.10.2 alias normalization (v2.3.4 behavior)")
    args = ap.parse_args()

    errors = validate(args.path.expanduser(), strict=args.strict)

    if errors:
        print("REPORT VALIDATION FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("REPORT VALIDATION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
