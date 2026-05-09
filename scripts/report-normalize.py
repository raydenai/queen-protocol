#!/usr/bin/env python3
"""Queen Protocol v2.11.0 — schema repair / report normalization (§29.5).

Real evidence (Elev-W1 colony, 2026-05-09): the queen manually rewrote
divergent ant reports into canonical form ("Ant's original report.json
was schema-pre-2.1 — replaced with this canonical version per QP §3.1"
— see C-phase0-eventrouter/report.json:queen_notes). This script
automates that repair pattern.

Inputs:
  --report <path>          The divergent report.json to repair
  --shard-id <id>          Canonical shard_id (used if report's is missing)
  --colony-id <id>         Used to look up plan.json for context
  --diff-file <path>       Optional: the actual diff for files_touched
                           ground truth (overrides reported list)
  --in-place               Overwrite the report file (default: stdout)

The script:
  1. Loads the divergent report
  2. Applies validate-report.py's normalize() pass (alias map + status case)
  3. Auto-fills missing required keys with reasonable defaults:
       schema_version       → "v2.4.0"
       shard_id             → from --shard-id or directory name
       attempt_id           → "a1"
       started_at           → file mtime - 600s (10 min ago) ISO8601
       finished_at          → file mtime ISO8601
       duration_seconds     → 600 (placeholder; real value lost)
       files_touched        → from --diff-file if provided, else []
       files_outside_allowed → []
       skills_loaded        → []
       gates                → [] (or normalize gates: object → list)
       tests_added          → []
       conflicts_with       → []
       assumptions          → []
       next_steps_for_queen → []
       ant_kind             → "queen-direct" (assume queen back-patch)
       diff_summary         → from existing notes/title/goal
  4. Preserves any queen_notes / operator_notes / audit_findings
  5. Writes a `repaired_at` field + `repaired_by: "report-normalize.py vX"`
     so the back-patch is auditable
  6. Validates the result against the strict schema; refuses to write if
     still failing (defensive)

Exit codes:
  0 — repaired report passes strict schema validation
  1 — repair failed; original errors emitted
  2 — config error (missing input file, etc.)
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

PROTO_DIR = Path(__file__).resolve().parent.parent
VALIDATE = PROTO_DIR / "scripts" / "validate-report.py"

REQUIRED_DEFAULTS: dict[str, Any] = {
    "schema_version": "v2.4.0",
    "attempt_id": "a1",
    "files_touched": [],
    "files_outside_allowed": [],
    "skills_loaded": [],
    "gates": [],
    "tests_added": [],
    "diff_summary": "",
    "conflicts_with": [],
    "assumptions": [],
    "next_steps_for_queen": [],
    "ant_kind": "queen-direct",
}

FIELD_ALIASES = {
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
}

STATUS_ALIASES = {
    "done": "DONE", "complete": "DONE", "completed": "DONE",
    "success": "DONE", "succeeded": "DONE",
    "fail": "FAILED", "failed": "FAILED", "error": "FAILED",
    "timeout": "TIMEOUT", "timed_out": "TIMEOUT",
}

GATE_STATUS_ALIASES = {
    "pass": "PASS", "passed": "PASS", "ok": "PASS", "green": "PASS",
    "fail": "FAIL", "failed": "FAIL", "error": "FAIL", "red": "FAIL",
    "skip": "SKIP", "skipped": "SKIP",
}


def iso_utc(dt: datetime) -> str:
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_diff_files_touched(diff_path: Path) -> list[str]:
    """Extract the set of files mentioned in a unified diff."""
    files: set[str] = set()
    for line in diff_path.read_text().splitlines():
        m = re.match(r"^(?:diff --git a/(\S+) b/\S+|\+\+\+ b/(\S+))", line)
        if m:
            files.add(m.group(1) or m.group(2))
    return sorted(files)


def normalize_report(
    raw: dict[str, Any],
    *,
    shard_id: str | None,
    diff_files_touched: list[str] | None,
    report_path: Path,
) -> dict[str, Any]:
    out = dict(raw)

    # 1. Field aliases
    for alias, canonical in FIELD_ALIASES.items():
        if alias in out and canonical not in out:
            out[canonical] = out.pop(alias)
        elif alias in out:
            out.pop(alias)

    # 2. Status case
    status = out.get("status")
    if isinstance(status, str):
        sl = status.strip().lower()
        if status.upper() in {"DONE", "FAILED", "TIMEOUT"}:
            out["status"] = status.upper()
        elif sl in STATUS_ALIASES:
            out["status"] = STATUS_ALIASES[sl]
    elif status is None:
        out["status"] = "DONE"  # Best-effort assumption when queen back-patches

    # 3. Gates: object → list, status case
    gates = out.get("gates")
    if isinstance(gates, dict):
        # Convert {name: status_str} or {name: {...}} into list
        new_gates = []
        for name, val in gates.items():
            if isinstance(val, dict):
                g = {"name": name, **val}
            else:
                g = {"name": name, "status": str(val)}
            new_gates.append(g)
        gates = new_gates
        out["gates"] = gates
    if not isinstance(gates, list):
        out["gates"] = []
    else:
        for g in out["gates"]:
            if not isinstance(g, dict):
                continue
            g.setdefault("command", "")
            g.setdefault("output_tail", "")
            g.setdefault("duration_ms", 0)
            gs = g.get("status")
            if isinstance(gs, str) and gs.upper() in {"PASS", "FAIL", "SKIP"}:
                g["status"] = gs.upper()
            elif isinstance(gs, str) and gs.strip().lower() in GATE_STATUS_ALIASES:
                g["status"] = GATE_STATUS_ALIASES[gs.strip().lower()]
            else:
                g["status"] = "SKIP"

    # 4. Required-field defaults
    for k, v in REQUIRED_DEFAULTS.items():
        if k not in out:
            out[k] = v

    # 5. shard_id / attempt_id
    if not out.get("shard_id"):
        out["shard_id"] = shard_id or report_path.parent.name

    # 6. Timing — derive from file mtime, anchored on finished_at to avoid
    # the tz-mixing pitfall where started_at (UTC mtime) ends up later than
    # finished_at (taken from a -07:00-offset timestamp field).
    file_mtime = datetime.fromtimestamp(report_path.stat().st_mtime, tz=UTC)
    if "wall_minutes" in raw and "duration_seconds" not in raw:
        try:
            out["duration_seconds"] = int(float(raw["wall_minutes"]) * 60)
        except (TypeError, ValueError):
            out["duration_seconds"] = 600
    if "duration_seconds" not in out:
        out["duration_seconds"] = 600
    if "finished_at" not in out:
        out["finished_at"] = iso_utc(file_mtime)

    def _parse_iso(s: str) -> datetime:
        try:
            return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        except (TypeError, ValueError):
            return file_mtime

    finished_dt = _parse_iso(out["finished_at"])
    try:
        dur_s = int(out.get("duration_seconds", 600))
    except (TypeError, ValueError):
        dur_s = 600

    # If started_at is missing OR appears later than finished_at, re-derive
    # from finished_at - duration. Always normalize to UTC to keep the
    # validator's lexicographic finished >= started comparison sound.
    started_present = "started_at" in out
    needs_rederive = not started_present
    if started_present:
        try:
            if _parse_iso(out["started_at"]) > finished_dt:
                needs_rederive = True
        except Exception:
            needs_rederive = True
    if needs_rederive:
        out["started_at"] = iso_utc(finished_dt - timedelta(seconds=dur_s))
    # Always re-emit finished_at in canonical UTC form
    out["finished_at"] = iso_utc(finished_dt)

    # 7. files_touched ground truth from diff if provided
    if diff_files_touched is not None:
        out["files_touched"] = diff_files_touched

    # 8. Coerce list-typed fields
    for arr in (
        "files_touched", "files_outside_allowed", "skills_loaded",
        "tests_added", "conflicts_with", "assumptions", "next_steps_for_queen",
    ):
        v = out.get(arr)
        if v is None:
            out[arr] = []
        elif isinstance(v, str):
            out[arr] = [v]
        elif not isinstance(v, list):
            out[arr] = []

    # 9. diff_summary fallback — synthesize from notes/title/goal if present
    if not out.get("diff_summary"):
        for src in ("notes", "title", "goal"):
            if raw.get(src):
                out["diff_summary"] = str(raw[src])[:1000]
                break

    # 10. Strip non-canonical keys (move to extras)
    canonical = set(REQUIRED_DEFAULTS.keys()) | {
        "schema_version", "shard_id", "attempt_id", "status",
        "started_at", "finished_at", "files_touched",
        "files_outside_allowed", "skills_loaded", "gates", "tests_added",
        "diff_summary", "conflicts_with", "assumptions",
        "next_steps_for_queen", "duration_seconds", "ant_kind",
    }
    allowed_extras = {
        "audit_findings", "findings", "verdict", "mode", "extra",
        "queen_notes", "operator_notes",
        "artifacts", "blocks_delivered", "critical_rules_verified",
        "migration",
    }
    keep_keys = canonical | allowed_extras
    extras: dict[str, Any] = {}
    for k in list(out.keys()):
        if k not in keep_keys:
            extras[k] = out.pop(k)
    if extras:
        out.setdefault("queen_notes", "")
        suffix = f"\n\n[normalize] preserved-extras: {json.dumps(extras)[:500]}"
        if isinstance(out["queen_notes"], str):
            out["queen_notes"] = (out["queen_notes"] + suffix).strip()
        else:
            out["queen_notes"] = suffix.strip()

    # 11. Audit trail
    out["queen_notes"] = (out.get("queen_notes", "") or "").strip()
    audit_line = f"[normalize] repaired by report-normalize.py v2.11.0 at {iso_utc(datetime.now(UTC))}"
    out["queen_notes"] = (out["queen_notes"] + ("\n\n" if out["queen_notes"] else "") + audit_line).strip()

    return out


def validate_strict(report_data: dict[str, Any]) -> list[str]:
    """Run validate-report.py --strict on a temp file and return errors."""
    tmp = Path("/tmp") / f".normalize-validate-{datetime.now(UTC).timestamp()}.json"
    tmp.write_text(json.dumps(report_data, indent=2))
    try:
        result = subprocess.run(
            [sys.executable, str(VALIDATE), "--strict", str(tmp)],
            capture_output=True, text=True, timeout=10,
        )
    finally:
        tmp.unlink(missing_ok=True)
    if result.returncode == 0:
        return []
    return [line for line in result.stderr.splitlines() if line.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--report", required=True, type=Path)
    ap.add_argument("--shard-id", default=None)
    ap.add_argument("--colony-id", default=None)
    ap.add_argument("--diff-file", default=None, type=Path)
    ap.add_argument("--in-place", action="store_true")
    args = ap.parse_args()

    if not args.report.exists():
        print(f"[normalize] report not found: {args.report}", file=sys.stderr)
        return 2

    try:
        raw = json.loads(args.report.read_text())
    except json.JSONDecodeError as e:
        print(f"[normalize] PARSE FAIL: {e}", file=sys.stderr)
        return 2

    diff_files = None
    if args.diff_file and args.diff_file.exists():
        diff_files = parse_diff_files_touched(args.diff_file)

    repaired = normalize_report(
        raw, shard_id=args.shard_id,
        diff_files_touched=diff_files,
        report_path=args.report,
    )

    errs = validate_strict(repaired)
    if errs:
        print("[normalize] repair FAILED — still invalid:", file=sys.stderr)
        for e in errs:
            print(f"  {e}", file=sys.stderr)
        return 1

    payload = json.dumps(repaired, indent=2)
    if args.in_place:
        args.report.write_text(payload + "\n")
        print(f"[normalize] repaired in place: {args.report}")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
