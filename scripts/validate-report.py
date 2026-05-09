#!/usr/bin/env python3
"""Queen Protocol v2.3.4 report validator.

Usage:
    python3 ~/.claude/scripts/validate-report.py <path-to-report.json>

Exit codes:
    0 — report is valid
    1 — schema violations (errors printed to stderr)
    2 — JSON parse failure

Run this BEFORE declaring __SHARD_DONE__. Queen also runs it at converge.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

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
ALLOWED_EXTRAS = {
    "audit_findings", "findings", "verdict", "mode", "extra",
    # v2.10.1 calibration: Elev-W1 colony (2026-05-09) used `queen_notes` as
    # a deliberate annotation slot on multiple shard reports. Schema accepts.
    "queen_notes", "operator_notes",
}
VALID_STATUS = {"DONE", "FAILED", "TIMEOUT"}
VALID_GATE_STATUS = {"PASS", "FAIL", "SKIP"}


def validate(path: Path) -> list[str]:
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
    if len(sys.argv) != 2:
        print(
            "usage: validate-report.py <path-to-report.json>", file=sys.stderr
        )
        return 1

    path = Path(sys.argv[1]).expanduser()
    errors = validate(path)

    if errors:
        print("REPORT VALIDATION FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("REPORT VALIDATION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
