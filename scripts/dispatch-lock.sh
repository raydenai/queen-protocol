#!/usr/bin/env bash
# Queen Protocol v2.13.0 — per-shard dispatch lock (§29.9).
#
# Real evidence (2026-05-09): two queens in two different tabs each
# dispatched X-test-repair within 10 seconds (PID 33077 mine, PID 34795
# the other tab's). The protocol's queen-lock prevents two queens
# RUNNING the same colony state machine simultaneously, but does NOT
# prevent two queens DISPATCHING the same shard id from different
# sessions. Result: duplicate Kimi cap consumption + worktree merge
# conflict at converge.
#
# This script provides a per-shard atomic lock written at dispatch
# time. Other queens see the lock and refuse-or-wait.
#
# Lock format (atomic mkdir + holder.json):
#   ~/.claude/state/colony/<colony-id>/shards/<shard-id>/dispatch.lock/
#       holder.json — {pid, queen_session, dispatched_at, prompt_hash}
#
# Usage:
#   dispatch-lock.sh acquire <colony-id> <shard-id> [--queen <name>]
#       Atomically write the lock. Exit 0 on success, 1 if held by
#       another queen, 2 on config error. Prints holder.json on conflict.
#
#   dispatch-lock.sh release <colony-id> <shard-id>
#       Remove the lock (e.g. after converge or cancellation).
#
#   dispatch-lock.sh check <colony-id> <shard-id>
#       Print current holder if locked, else exit 1.
#
#   dispatch-lock.sh sweep <colony-id>
#       Find stale locks (holder PID dead OR age > 4h with no report)
#       and print their paths. Operator decides removal.
#
# Wraps mkdir's atomicity (POSIX-portable), no flock dependency.

set -euo pipefail

STATE_ROOT="${HOME}/.claude/state/colony"

usage() {
    cat <<EOF
dispatch-lock.sh — per-shard atomic dispatch lock (Queen Protocol v2.13.0).

Subcommands:
  acquire <colony-id> <shard-id> [--queen <name>] [--prompt-hash <h>]
      Acquire lock atomically. Exit 0 success, 1 conflict, 2 config error.
  release <colony-id> <shard-id>
      Remove the lock (after converge / cancellation).
  check <colony-id> <shard-id>
      Print holder JSON if locked, exit 0; exit 1 if not locked.
  sweep <colony-id>
      List stale locks: holder PID dead OR shard older than 4h with no report.
  help
      This message.
EOF
}

CMD="${1:-help}"
shift || true

shard_dir() { echo "${STATE_ROOT}/$1/shards/$2"; }
lock_dir() { echo "$(shard_dir "$1" "$2")/dispatch.lock"; }
holder() { echo "$(lock_dir "$1" "$2")/holder.json"; }

cmd_acquire() {
    local colony="$1" shard="$2"
    local queen="$$" prompt_hash=""
    shift 2 2>/dev/null || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --queen)       queen="$2"; shift 2 ;;
            --prompt-hash) prompt_hash="$2"; shift 2 ;;
            *) echo "unknown flag: $1" >&2; exit 2 ;;
        esac
    done
    [[ -z "$colony" || -z "$shard" ]] && { usage; exit 2; }

    mkdir -p "$(shard_dir "$colony" "$shard")"
    local ld
    ld="$(lock_dir "$colony" "$shard")"

    # mkdir is atomic — succeeds for exactly one caller, fails for others
    if mkdir "$ld" 2>/dev/null; then
        local ts
        ts="$(date -u +%FT%TZ)"
        # Use env vars to safely pass values into Python without quoting hell
        DL_PID="$$" DL_QUEEN="$queen" DL_TS="$ts" DL_PROMPT_HASH="$prompt_hash" \
            python3 -c "
import json, os
print(json.dumps({
    'pid': os.environ.get('DL_PID', ''),
    'queen': os.environ.get('DL_QUEEN', ''),
    'dispatched_at': os.environ.get('DL_TS', ''),
    'prompt_hash': os.environ.get('DL_PROMPT_HASH', ''),
}, indent=2))" > "$(holder "$colony" "$shard")"
        echo "[lock] ACQUIRED $colony/$shard (queen=$queen)"
        exit 0
    fi

    # Lock held — print existing holder for the other queen's diagnostics
    echo "[lock] CONFLICT — $colony/$shard already locked:" >&2
    cat "$(holder "$colony" "$shard")" 2>/dev/null | sed 's/^/    /' >&2
    exit 1
}

cmd_release() {
    local colony="$1" shard="$2"
    [[ -z "$colony" || -z "$shard" ]] && { usage; exit 2; }
    local ld
    ld="$(lock_dir "$colony" "$shard")"
    if [[ -d "$ld" ]]; then
        rm -rf "$ld"
        echo "[lock] RELEASED $colony/$shard"
    else
        echo "[lock] (not held) $colony/$shard"
    fi
}

cmd_check() {
    local colony="$1" shard="$2"
    [[ -z "$colony" || -z "$shard" ]] && { usage; exit 2; }
    local h
    h="$(holder "$colony" "$shard")"
    if [[ -f "$h" ]]; then
        cat "$h"
        exit 0
    fi
    exit 1
}

cmd_sweep() {
    local colony="$1"
    [[ -z "$colony" ]] && { usage; exit 2; }
    local sd="${STATE_ROOT}/${colony}/shards"
    [[ ! -d "$sd" ]] && exit 0

    local stale=0
    local now
    now="$(date +%s)"
    while IFS= read -r -d '' h; do
        local ld
        ld="$(dirname "$h")"
        local shard_d
        shard_d="$(dirname "$ld")"
        local pid
        pid=$(python3 -c "import json; print(json.load(open('$h')).get('pid',''))" 2>/dev/null || echo "")

        # Stale if PID is set + dead, or if no report yet AND >4h old
        local stale_reason=""
        if [[ -n "$pid" && "$pid" != "$$" ]] && ! ps -p "$pid" >/dev/null 2>&1; then
            stale_reason="pid=$pid is dead"
        else
            local mtime
            mtime=$(stat -f%m "$h" 2>/dev/null || stat -c%Y "$h" 2>/dev/null || echo "$now")
            local age_h=$(( (now - mtime) / 3600 ))
            if [[ $age_h -gt 4 && ! -f "${shard_d}/report.json" ]]; then
                stale_reason="age=${age_h}h with no report.json"
            fi
        fi

        if [[ -n "$stale_reason" ]]; then
            echo "STALE_LOCK: $ld ($stale_reason)"
            stale=$((stale+1))
        fi
    done < <(find "$sd" -name 'holder.json' -path '*/dispatch.lock/*' -print0 2>/dev/null)

    [[ $stale -eq 0 ]] && echo "[sweep] no stale locks in $colony"
}

case "$CMD" in
    acquire) cmd_acquire "$@" ;;
    release) cmd_release "$@" ;;
    check)   cmd_check "$@" ;;
    sweep)   cmd_sweep "$@" ;;
    help|--help|-h|"") usage ;;
    *) echo "unknown command: $CMD" >&2; usage; exit 2 ;;
esac
