#!/usr/bin/env python3
"""Queen Protocol v2.7.0 — migration number reservation (§25.15).

Real evidence (2026-05-08): commit `fdad578 feat(db): migration 0047 — extend
cz_themes to support sites` carries the body note "Renamed from 0037 → 0047
to resolve number collision with 0037_event_fanout_columns.sql (Phase D.1,
committed in ec1c1c2)". Two parallel streams (one tab shipping Phase D.1,
another tab shipping cz_themes site extension) both grabbed `0037` for their
new migration. The collision was caught at PR review and fixed by manual
renumber, but the same race could just as easily ship two production
migrations with the same number to two different environments.

This script reserves migration numbers at PLAN time. Reading the colony
plan, it computes how many migrations the colony will add (sum of
shards[*].adds_migrations), scans the migration directory for the highest
existing number, and reserves a contiguous block starting at max+1. Reserved
numbers are written into the colony's plan.json under `reserved_migrations`
so each ant can be told its assigned number deterministically rather than
guessing.

Usage:
    python3 migration-number-reserve.py \\
        --plan ~/.claude/state/colony/<id>/plan.json \\
        --migrations-dir /path/to/repo/supabase/migrations \\
        [--write]   # update plan.json in-place; otherwise dry-run

Exit codes:
    0  — reservation written (or dry-run preview emitted)
    1  — collision detected with another colony's already-reserved range
    2  — config error

Plan schema additions:
    shards[].adds_migrations: int (default 0) — how many migration files
                                                 this shard will create
    reserved_migrations: {
        "first": int,
        "last": int,
        "by_shard": { "<shard_id>": [int, ...] }
    }
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


MIGRATION_RE = re.compile(r"^(\d{4})_")


def find_existing_max(migrations_dir: Path) -> int:
    if not migrations_dir.exists():
        return -1
    nums: list[int] = []
    for p in migrations_dir.iterdir():
        m = MIGRATION_RE.match(p.name)
        if m:
            nums.append(int(m.group(1)))
    return max(nums) if nums else -1


def find_other_colony_reservations(self_plan_path: Path) -> list[tuple[int, int, str]]:
    """Scan ~/.claude/state/colony/*/plan.json for active reservations.

    Returns list of (first, last, colony_id) for colonies that are not yet
    LANDED. Used to detect races between simultaneous queens.
    """
    state_root = self_plan_path.parent.parent
    found: list[tuple[int, int, str]] = []
    for plan_path in state_root.glob("*/plan.json"):
        if plan_path.resolve() == self_plan_path.resolve():
            continue
        try:
            data = json.loads(plan_path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        active = state_root / plan_path.parent.name / "active.json"
        if active.exists():
            try:
                act = json.loads(active.read_text())
                if act.get("phase") == "LANDED":
                    continue
            except Exception:
                pass
        rsv = data.get("reserved_migrations")
        if rsv and "first" in rsv and "last" in rsv:
            found.append((rsv["first"], rsv["last"], data.get("colony_id", plan_path.parent.name)))
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--migrations-dir", required=True, type=Path)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    if not args.plan.exists():
        print(f"[reserve] plan not found: {args.plan}", file=sys.stderr)
        return 2

    plan = json.loads(args.plan.read_text())
    shards = plan.get("shards", [])
    total_needed = sum(int(s.get("adds_migrations", 0) or 0) for s in shards)

    if total_needed == 0:
        print("[reserve] no shards declare adds_migrations > 0; nothing to reserve")
        return 0

    existing_max = find_existing_max(args.migrations_dir)
    others = find_other_colony_reservations(args.plan)
    other_max = max((last for _, last, _ in others), default=-1)
    floor = max(existing_max, other_max)
    first = floor + 1
    last = first + total_needed - 1

    # Detect overlap with active other-colony reservations
    for o_first, o_last, cid in others:
        if not (last < o_first or first > o_last):
            print(
                f"[reserve] COLLISION with colony {cid} reservation "
                f"{o_first:04d}..{o_last:04d}; refusing to write",
                file=sys.stderr,
            )
            return 1

    # Assign numbers per shard in plan order
    cursor = first
    by_shard: dict[str, list[int]] = {}
    for shard in shards:
        n = int(shard.get("adds_migrations", 0) or 0)
        if n <= 0:
            continue
        by_shard[shard["id"]] = list(range(cursor, cursor + n))
        cursor += n

    reservation = {
        "first": first,
        "last": last,
        "by_shard": by_shard,
        "existing_max_at_plan": existing_max,
    }

    if args.write:
        plan["reserved_migrations"] = reservation
        args.plan.write_text(json.dumps(plan, indent=2) + "\n")
        print(f"[reserve] wrote reservation {first:04d}..{last:04d} into {args.plan}")
    else:
        print("[reserve] DRY-RUN — would reserve:")
        print(json.dumps(reservation, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
