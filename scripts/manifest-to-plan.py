#!/usr/bin/env python3
"""Queen Protocol v2.10.0 — MANIFEST.md → plan.json bridge (§28.2).

Real evidence (Elev-W1 colony, 2026-05-09): operators in production write
human-readable MANIFEST.md tables to declare colony intent, while runtime
gates (validate-report.py, cross-shard-audit.py, colony-converge.sh) require
machine-readable plan.json. The two formats diverged: queen-runtime saw "no
plan.json — skipping" and gates degraded silently.

This script parses a MANIFEST.md table into a plan.json so the runtime gates
can read a queen-operator's declared intent.

Expected MANIFEST.md table format (the one actually shipped in
~/.claude/state/colony/2026-05-09-elev-w1/MANIFEST.md):

    ## Shards

    | ID | Title | Cap# | Risk | Backend | Deadline | Files Allowed |
    |---|---|---|---|---|---|---|
    | A-cap4-edit-path | ... | #4 | Medium | kimi-isolated | 75 min | path1, path2 |
    | B-cap7-wallet | ... | #7 | High | kimi-isolated | 90 min | path3 |
    | C-phase0-eventrouter | ... | #12 | Medium | kimi-isolated | 90 min | path4 |

Usage:
    python3 manifest-to-plan.py \\
        --colony-id 2026-05-09-elev-w1 \\
        --manifest ~/.claude/state/colony/2026-05-09-elev-w1/MANIFEST.md \\
        [--write]

The output plan.json is written to:
    ~/.claude/state/colony/<colony-id>/plan.json

Exit 0 on success, 2 on parse error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def parse_manifest(path: Path) -> tuple[str, list[dict[str, Any]]]:
    """Returns (objective, shards). Raises on parse failure."""
    text = path.read_text()

    # Title for objective
    title_m = re.search(r"^# (.+)$", text, re.MULTILINE)
    objective = title_m.group(1).strip() if title_m else f"Colony from {path.name}"

    # Find the shards table — first markdown table after "## Shards"
    shards_section = re.search(
        r"^## Shards\s*\n(.*?)(?=\n## |\Z)", text, re.MULTILINE | re.DOTALL
    )
    if not shards_section:
        raise ValueError("No '## Shards' section found")

    table = shards_section.group(1)
    rows = [
        line.strip() for line in table.splitlines()
        if line.strip().startswith("|") and not re.match(r"^\|[\s\-|]+\|$", line.strip())
    ]
    if len(rows) < 2:
        raise ValueError("Shards table needs header + at least one row")

    header = [c.strip().lower() for c in rows[0].strip("|").split("|")]
    shards: list[dict[str, Any]] = []
    for row in rows[1:]:
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) != len(header):
            continue
        d = dict(zip(header, cells, strict=False))
        shard_id = d.get("id", "").strip()
        if not shard_id:
            continue

        # Files allowed: comma- or backtick-separated paths in the cell
        files_raw = d.get("files allowed", d.get("files", ""))
        files_allowed = [
            p.strip().strip("`").strip("'").strip('"')
            for p in re.split(r"[,;]", files_raw)
            if p.strip()
        ]

        # Backend
        backend = d.get("backend", "kimi-isolated").strip()
        ant_kind = backend
        if backend.startswith("kimi"):
            ant_kind = "kimi-isolated"
        elif "claude" in backend:
            ant_kind = "claude-ant"
        elif "codex" in backend:
            ant_kind = "agent:codex-rescue"
        elif "g4" in backend or "gemma" in backend:
            ant_kind = "g4-local"

        # Deadline
        deadline_str = d.get("deadline", "")
        m = re.search(r"(\d+)\s*min", deadline_str)
        deadline_min = int(m.group(1)) if m else 90

        # Risk → priority mapping
        risk = d.get("risk", "Medium").strip().lower()
        priority = {"low": "p3", "medium": "p2", "high": "p1", "critical": "critical"}.get(
            risk.split()[0] if risk else "medium", "p2"
        )

        # Tags from title or risk text — heuristic
        title = d.get("title", "")
        tags: list[str] = []
        for keyword, tag in [
            ("stripe", "payment"),
            ("payment", "payment"),
            ("wallet", "payment"),
            ("auth", "auth"),
            ("rls", "security-critical"),
            ("migration", "migration"),
            ("idempotency", "idempotency"),
            ("eventrouter", "infrastructure"),
            ("ai gen", "agent"),
            ("orchestrat", "orchestrator"),
        ]:
            if keyword in title.lower() or keyword in risk:
                tags.append(tag)
        # Production-path detection
        prod_globs = [
            "supabase/migrations/", "stripe", ".env.production",
            "auth", "billing", "payments",
        ]
        if any(g in " ".join(files_allowed).lower() for g in prod_globs):
            tags.append("production-path")

        shards.append({
            "id": shard_id,
            "title": title,
            "ant_kind": ant_kind,
            "priority": priority,
            "tags": list(dict.fromkeys(tags)),
            "files_allowed": files_allowed,
            "deadline_minutes": deadline_min,
            "objective": title,
        })

    return objective, shards


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--colony-id", required=True)
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    if not args.manifest.exists():
        print(f"[manifest] not found: {args.manifest}", file=sys.stderr)
        return 2

    try:
        objective, shards = parse_manifest(args.manifest)
    except ValueError as e:
        print(f"[manifest] parse failed: {e}", file=sys.stderr)
        return 2

    plan = {
        "colony_id": args.colony_id,
        "schema_version": "v2.10.0",
        "mode": "default",
        "objective": objective,
        "source": f"converted from {args.manifest.name} via manifest-to-plan.py",
        "shards": shards,
    }

    out = Path.home() / ".claude" / "state" / "colony" / args.colony_id / "plan.json"
    if args.write:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(plan, indent=2) + "\n")
        print(f"[manifest] wrote plan.json with {len(shards)} shards → {out}")
    else:
        print(f"[manifest] DRY-RUN — would write plan with {len(shards)} shards:")
        for s in shards:
            print(f"  {s['id']}: {s['ant_kind']} priority={s['priority']} "
                  f"tags={s['tags']} deadline={s['deadline_minutes']}min")
    return 0


if __name__ == "__main__":
    sys.exit(main())
