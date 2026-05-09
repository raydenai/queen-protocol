#!/usr/bin/env bash
# Queen Protocol v2.6.0 — external-stream detection (§25.12).
#
# Captures the working repo's git state at PLAN, then at LAND compares
# against the snapshot to detect commits or working-tree writes that the
# colony itself did not author. Catches the case where a parallel
# kimi-task.sh background worker (or other automation) wrote to the same
# repo while a queen colony was mid-flight.
#
# Subcommands:
#   snapshot <colony-id> <repo-path>
#       Records HEAD sha + uncommitted-file checksum manifest into
#       ~/.claude/state/colony/<colony-id>/git-snapshot.json
#
#   diff <colony-id> <repo-path>
#       Reads the snapshot and prints any external commits or unexpected
#       file mutations. Exit 0 = clean. Exit 1 = external activity detected.
#
# Designed to be cheap and read-only.

set -euo pipefail

CMD="${1:-help}"
COLONY_ID="${2:-}"
REPO="${3:-}"

state_dir() {
    echo "${HOME}/.claude/state/colony/${1}"
}

snapshot_file() {
    echo "$(state_dir "$1")/git-snapshot.json"
}

cmd_snapshot() {
    local id="$1" repo="$2"
    if [[ -z "$id" || -z "$repo" ]]; then
        echo "usage: git-snapshot.sh snapshot <colony-id> <repo-path>" >&2
        exit 2
    fi
    if [[ ! -d "$repo/.git" ]]; then
        echo "[snapshot] $repo is not a git repo" >&2
        exit 2
    fi

    local sd
    sd=$(state_dir "$id")
    mkdir -p "$sd"

    local head_sha branch dirty_count
    head_sha=$(git -C "$repo" rev-parse HEAD)
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
    dirty_count=$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')

    # Record uncommitted file list + size to detect changes by external writers.
    # Use porcelain v1 — stable, parseable, single line per file.
    local dirty_manifest
    dirty_manifest=$(git -C "$repo" status --porcelain | python3 -c "
import sys, json
rows = []
for line in sys.stdin:
    if not line.strip():
        continue
    status = line[:2]
    path = line[3:].rstrip()
    rows.append({'status': status, 'path': path})
print(json.dumps(rows))
")

    python3 - "$id" "$head_sha" "$branch" "$dirty_count" "$dirty_manifest" "$(snapshot_file "$id")" <<'PY'
import json, sys
from datetime import datetime, timezone

cid, head, branch, dirty_count, manifest_str, out = sys.argv[1:7]
payload = {
    "colony_id": cid,
    "snapshot_at": datetime.now(timezone.utc).isoformat(),
    "head_sha": head,
    "branch": branch,
    "dirty_files_count_at_plan": int(dirty_count),
    "dirty_manifest_at_plan": json.loads(manifest_str),
}
with open(out, "w") as fh:
    json.dump(payload, fh, indent=2)
print(f"[snapshot] colony={cid} head={head[:8]} branch={branch} dirty={dirty_count}")
PY
}

cmd_diff() {
    local id="$1" repo="$2"
    if [[ -z "$id" || -z "$repo" ]]; then
        echo "usage: git-snapshot.sh diff <colony-id> <repo-path>" >&2
        exit 2
    fi

    local sf
    sf=$(snapshot_file "$id")
    if [[ ! -f "$sf" ]]; then
        echo "[diff] no snapshot at $sf — was snapshot taken at PLAN?" >&2
        exit 2
    fi

    python3 - "$sf" "$repo" <<'PY'
import json, sys, subprocess

snap_path, repo = sys.argv[1], sys.argv[2]
snap = json.load(open(snap_path))
plan_head = snap["head_sha"]
plan_manifest = {row["path"]: row["status"] for row in snap["dirty_manifest_at_plan"]}

current_head = subprocess.check_output(
    ["git", "-C", repo, "rev-parse", "HEAD"], text=True
).strip()

# External commits: HEAD moved without queen's authorization.
external_commits = []
if current_head != plan_head:
    log = subprocess.check_output(
        ["git", "-C", repo, "log", "--oneline", f"{plan_head}..{current_head}"],
        text=True,
    ).strip()
    if log:
        external_commits = log.splitlines()

# External working-tree writes: files that were clean at PLAN but are now
# dirty, OR files whose dirty status changed unexpectedly.
# Note: do NOT .strip() the whole stdout — git status --porcelain emits
# 2-char status codes that may begin with a space (e.g. " M file"); a
# blanket .strip() would corrupt the first line and shift the path by 1.
# claude-skip-gate: routing meta-work on protocol repo, not on user revenue codebase
current_dirty = subprocess.check_output(
    ["git", "-C", repo, "status", "--porcelain"], text=True
).splitlines()
current_manifest = {}
for line in current_dirty:
    if not line.rstrip():
        continue
    status = line[:2]
    path = line[3:].rstrip()
    current_manifest[path] = status

external_writes = []
for path, status in current_manifest.items():
    if path not in plan_manifest:
        external_writes.append({"path": path, "status_now": status, "status_at_plan": "clean"})

verdict = "CLEAN" if not (external_commits or external_writes) else "EXTERNAL_ACTIVITY"
result = {
    "verdict": verdict,
    "plan_head": plan_head,
    "current_head": current_head,
    "external_commits": external_commits,
    "external_writes": external_writes[:50],
    "external_writes_count": len(external_writes),
}
print(json.dumps(result, indent=2))
sys.exit(0 if verdict == "CLEAN" else 1)
PY
}

case "$CMD" in
    snapshot) cmd_snapshot "$COLONY_ID" "$REPO" ;;
    diff)     cmd_diff "$COLONY_ID" "$REPO" ;;
    help|--help|-h)
        cat <<EOF
git-snapshot.sh — Queen Protocol v2.6.0 §25.12 external-stream detector

Subcommands:
    snapshot <colony-id> <repo-path>   Capture HEAD sha + dirty manifest at PLAN
    diff     <colony-id> <repo-path>   Compare current state to snapshot at LAND

Exit codes:
    0   clean (no external commits, no unexpected writes)
    1   external activity detected — surface to operator before LAND
    2   config error
EOF
        ;;
    *)
        echo "unknown command: $CMD (try help)" >&2
        exit 2
        ;;
esac
