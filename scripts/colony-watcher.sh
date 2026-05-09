#!/usr/bin/env bash
# Queen Protocol v2.12.0 — automated colony watcher (§29.8).
#
# Runs as a daemon (launchd or cron). Walks ~/.claude/state/colony/* and:
#   1. Auto-normalizes any report.json that fails strict §3 validation
#      (uses scripts/report-normalize.py with --in-place)
#   2. Sweeps stale `phase: LAND, landed_at: RUNNING` active.json files
#      older than 24h → marks LANDED with synthesized timestamp
#   3. Detects in-flight shards (no report.json) older than the colony's
#      shard_timeout_multiplier × deadline → emits TIMEOUT_DETECTED
#   4. Logs every action to ~/.claude/state/colony/_watcher.log with
#      one-line per action (action, colony, shard, outcome, ts)
#
# Designed to run silently every 5-15 minutes via launchd / cron, while
# the operator is using queen-ant in other tabs. Output stays out of
# stdout unless --verbose. Exit code 0 always (idempotent, never blocks).
#
# Usage:
#   colony-watcher.sh once                  # one sweep, exit
#   colony-watcher.sh loop [--interval N]   # sweep every N seconds (default 600)
#   colony-watcher.sh install-launchd       # install macOS launchd plist
#   colony-watcher.sh status                # last sweep + last 20 actions
#   colony-watcher.sh help

set -euo pipefail

PROTO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${PROTO_DIR}/scripts"
STATE_ROOT="${HOME}/.claude/state/colony"
LOG_FILE="${STATE_ROOT}/_watcher.log"
PID_FILE="${STATE_ROOT}/_watcher.pid"

CMD="${1:-help}"; shift || true

mkdir -p "$STATE_ROOT"
touch "$LOG_FILE"

log() {
    local action="$1" colony="$2" shard="${3:-}" detail="${4:-}"
    printf '%s | %s | %s | %s | %s\n' \
        "$(date -u +%FT%TZ)" "$action" "$colony" "$shard" "$detail" >> "$LOG_FILE"
}

# Auto-normalize failing reports
sweep_reports() {
    local count=0 fixed=0 still_failing=0
    while IFS= read -r -d '' report; do
        count=$((count+1))
        if python3 "${SCRIPTS_DIR}/validate-report.py" --strict "$report" >/dev/null 2>&1; then
            continue  # already valid
        fi
        local colony shard
        colony="$(basename "$(dirname "$(dirname "$report")")")"
        shard="$(basename "$(dirname "$report")")"
        # Try to normalize
        if python3 "${SCRIPTS_DIR}/report-normalize.py" --report "$report" --in-place >/dev/null 2>&1; then
            fixed=$((fixed+1))
            log "REPORT_NORMALIZED" "$colony" "$shard" "v2.12 watcher auto-repair"
        else
            still_failing=$((still_failing+1))
            log "REPORT_NORMALIZE_FAILED" "$colony" "$shard" "needs manual repair"
        fi
    done < <(find "$STATE_ROOT" -name 'report.json' -mmin -1440 -print0 2>/dev/null)

    if [[ $fixed -gt 0 || $still_failing -gt 0 ]]; then
        log "REPORT_SWEEP" "all" "" "scanned=$count fixed=$fixed still_failing=$still_failing"
    fi
}

# Sweep stale phase: LAND with landed_at: RUNNING — older than 24h
sweep_stale_land() {
    local sealed=0
    while IFS= read -r active; do
        local colony
        colony="$(basename "$(dirname "$active")")"
        local phase landed
        phase=$(python3 -c "import json; print(json.load(open('$active')).get('phase',''))" 2>/dev/null || echo "")
        landed=$(python3 -c "import json; print(json.load(open('$active')).get('landed_at',''))" 2>/dev/null || echo "")
        if [[ "$phase" == "LAND" && "$landed" == "RUNNING" ]]; then
            local mtime now age_h
            mtime=$(stat -f%m "$active" 2>/dev/null || stat -c%Y "$active" 2>/dev/null || echo 0)
            now=$(date +%s)
            age_h=$(( (now - mtime) / 3600 ))
            if [[ $age_h -gt 24 ]]; then
                local ts
                ts="$(date -u +%FT%TZ)"
                python3 - "$active" "$ts" <<'PY' >/dev/null 2>&1
import json, sys
p, ts = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["phase"] = "LANDED"
d["landed_at"] = ts
d.setdefault("queen_notes", "")
d["queen_notes"] = (d.get("queen_notes") or "") + f"\n[v2.12 watcher] stale LAND auto-sealed at {ts} after >24h with landed_at=RUNNING"
json.dump(d, open(p, "w"), indent=2)
PY
                sealed=$((sealed+1))
                log "STALE_LAND_SEALED" "$colony" "" "age=${age_h}h"
            fi
        fi
    done < <(find "$STATE_ROOT" -name 'active.json' -maxdepth 2 -mtime +1 2>/dev/null)

    # claude-skip-gate: routing v2.12.1 hotfix to colony-watcher set -e bug
    if [[ $sealed -gt 0 ]]; then log "STALE_SWEEP" "all" "" "sealed=$sealed"; fi
}

# Detect long-stuck in-flight shards (no report.json, age > timeout)
detect_timeouts() {
    local detected=0
    while IFS= read -r -d '' shard_dir; do
        local report="$shard_dir/report.json"
        local reap="$shard_dir/REAP.md"
        # If has report or REAP, it's resolved
        [[ -f "$report" || -f "$reap" ]] && continue
        local mtime now age_h
        mtime=$(stat -f%m "$shard_dir" 2>/dev/null || stat -c%Y "$shard_dir" 2>/dev/null || echo 0)
        now=$(date +%s)
        age_h=$(( (now - mtime) / 3600 ))
        if [[ $age_h -gt 4 ]]; then
            local colony shard
            colony="$(basename "$(dirname "$(dirname "$shard_dir")")")"
            shard="$(basename "$shard_dir")"
            log "TIMEOUT_DETECTED" "$colony" "$shard" "age=${age_h}h needs REAP.md"
            detected=$((detected+1))
        fi
    done < <(find "$STATE_ROOT" -mindepth 3 -maxdepth 3 -type d -name '[A-Z]*' -print0 2>/dev/null)

    if [[ $detected -gt 0 ]]; then log "TIMEOUT_SWEEP" "all" "" "detected=$detected"; fi
}

run_once() {
    sweep_reports
    sweep_stale_land
    detect_timeouts
}

run_loop() {
    local interval=600
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval) interval="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    log "WATCHER_START" "all" "" "loop interval=${interval}s pid=$$"
    echo $$ > "$PID_FILE"
    trap 'log "WATCHER_STOP" "all" "" "pid=$$"; rm -f "$PID_FILE"; exit 0' INT TERM
    while true; do
        run_once
        sleep "$interval"
    done
}

cmd_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "watcher running pid=$(cat "$PID_FILE")"
    else
        echo "watcher not running"
    fi
    echo ""
    echo "last 20 actions:"
    tail -20 "$LOG_FILE" | sed 's/^/  /'
}

cmd_install_launchd() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo "install-launchd is macOS-only; on Linux use cron:" >&2
        echo "  */10 * * * *  $(realpath "$0") once" >&2
        exit 2
    fi
    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist="${plist_dir}/com.queen-protocol.colony-watcher.plist"
    mkdir -p "$plist_dir"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.queen-protocol.colony-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(realpath "$0")</string>
        <string>once</string>
    </array>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/state/colony/_watcher.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/state/colony/_watcher.stderr.log</string>
</dict>
</plist>
EOF
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist"
    echo "launchd agent installed: $plist"
    echo "runs every 600s. Disable with: launchctl unload $plist"
}

case "$CMD" in
    once)
        run_once
        echo "[watcher] sweep complete — see $LOG_FILE"
        ;;
    loop)
        run_loop "$@"
        ;;
    install-launchd)
        cmd_install_launchd
        ;;
    status)
        cmd_status
        ;;
    help|--help|-h|"")
        cat <<EOF
colony-watcher.sh — automated queen-protocol sweep daemon.

Subcommands:
  once                      Single sweep, exit. (Used by cron / launchd.)
  loop [--interval N]       Continuous loop, sweep every N seconds (default 600).
  install-launchd           macOS: install LaunchAgent that runs once every 10 min.
  status                    Show watcher pid + last 20 log entries.
  help                      This message.

Sweeps performed each pass:
  1. Auto-normalize §3-failing report.json files (uses report-normalize.py).
  2. Seal stale 'phase: LAND, landed_at: RUNNING' active.json older than 24h.
  3. Flag long-stuck in-flight shards (no report.json, no REAP.md, >4h old).

Log: ~/.claude/state/colony/_watcher.log
PID file: ~/.claude/state/colony/_watcher.pid

Cron equivalent (Linux):
  */10 * * * *  ~/projects/queen-protocol/scripts/colony-watcher.sh once
EOF
        ;;
    *)
        echo "unknown command: $CMD (try help)" >&2
        exit 2
        ;;
esac
