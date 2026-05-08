#!/usr/bin/env bash
# Queen Protocol v2.4.0 — meshboard adapter
#
# Streams queen-protocol telemetry events into meshboard's /api/colony/message
# endpoint. Replaces the v2.3.2 (wrong) claim that meshboard's built-in
# colony_ops_producer would tail telemetry.jsonl directly — it doesn't.
#
# Usage:
#   colony-meshboard-adapter.sh \
#       --watch ~/.claude/state/colony \
#       --api  http://localhost:8585/api/colony/message
#
# Run as a background daemon (nohup ... &) per colony session.

set -euo pipefail

WATCH_DIR="${HOME}/.claude/state/colony"
API_URL="http://localhost:8585/api/colony/message"
POLL_INTERVAL=1.0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch) WATCH_DIR="$2"; shift 2 ;;
        --api)   API_URL="$2"; shift 2 ;;
        --poll)  POLL_INTERVAL="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
Usage: colony-meshboard-adapter.sh [--watch DIR] [--api URL] [--poll SECS]

  --watch DIR   Directory to watch for telemetry.jsonl changes
                (default: \$HOME/.claude/state/colony)
  --api URL     meshboard endpoint to POST events to
                (default: http://localhost:8585/api/colony/message)
  --poll SECS   Poll interval (default: 1.0; lower = lower latency)
EOF
            exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -d "$WATCH_DIR" ]]; then
    echo "Watch dir does not exist: $WATCH_DIR" >&2
    exit 2
fi

# Track byte offsets per file so we resume from where we left off
STATE_DIR="${HOME}/.claude/state/colony-adapter"
mkdir -p "$STATE_DIR"

# Map shard_id prefix -> meshboard's allowlisted node bucket
# meshboard hardcodes {eagle, titan, nova, poseidon, dr_umit}; map our shard
# domains to those names so events appear in the dashboard.
bucket_for_shard() {
    local sid="$1"
    case "$sid" in
        *backend*|*api*|*route*|*payment*|*stripe*|*supabase*) echo "eagle" ;;
        *frontend*|*dashboard*|*wizard*|*ui*|*public*|*astro*) echo "titan" ;;
        *orchestrator*|*agent*|*pipeline*|*audit*) echo "nova" ;;
        *test*|*spec*|*coverage*) echo "poseidon" ;;
        *) echo "dr_umit" ;;
    esac
}

# Map queen event type -> meshboard message_type
mtype_for_event() {
    case "$1" in
        DISPATCH)              echo "task.start" ;;
        STATE_TRANSITION)      echo "task.update" ;;
        LAND)                  echo "task.complete" ;;
        REPORT_REJECTED|GATE_RERUN_DISAGREE|CONFLICT) echo "task.fail" ;;
        SCHEMA_VALIDATOR_PASS) echo "task.update" ;;
        SECURITY_*)            echo "task.fail" ;;
        *)                     echo "task.update" ;;
    esac
}

# Process one telemetry line: parse, transform, POST
process_line() {
    local colony_id="$1"
    local line="$2"

    # Use python to parse the JSON line (jq might not be installed)
    python3 - "$colony_id" "$line" "$API_URL" <<'PYEOF'
import json, sys, urllib.request, urllib.error

colony_id, line, api_url = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    evt = json.loads(line)
except Exception:
    sys.exit(0)  # skip malformed lines silently

shard_id = evt.get("shard_id") or evt.get("colony_id") or colony_id
event_type = evt.get("event", "UNKNOWN")

# Bucket map per the shell function above (Python copy for inline use)
def bucket(sid):
    sid = (sid or "").lower()
    if any(k in sid for k in ("backend","api","route","payment","stripe","supabase")): return "eagle"
    if any(k in sid for k in ("frontend","dashboard","wizard","ui","public","astro")): return "titan"
    if any(k in sid for k in ("orchestrator","agent","pipeline","audit")): return "nova"
    if any(k in sid for k in ("test","spec","coverage")): return "poseidon"
    return "dr_umit"

mtype_map = {
    "DISPATCH": "task.start",
    "STATE_TRANSITION": "task.update",
    "LAND": "task.complete",
    "REPORT_REJECTED": "task.fail",
    "GATE_RERUN_DISAGREE": "task.fail",
    "CONFLICT": "task.fail",
    "SCHEMA_VALIDATOR_PASS": "task.update",
}
message_type = mtype_map.get(event_type, "task.update")
if event_type.startswith("SECURITY_"):
    message_type = "task.fail"

text_bits = [event_type]
for k in ("from", "to", "backend", "reason", "verdict"):
    if k in evt:
        text_bits.append(f"{k}={evt[k]}")
text = " | ".join(text_bits)[:240]

payload = {
    "colony_id": colony_id,
    "queen_event": event_type,
    "raw": evt,
}

body = json.dumps({
    "from_agent": "poseidon",
    "to_agent": bucket(shard_id),
    "text": text,
    "message_type": message_type,
    "payload": payload,
}).encode()

req = urllib.request.Request(
    api_url, data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        resp.read()
except urllib.error.HTTPError as e:
    print(f"[adapter] HTTP {e.code}: {e.reason} for {event_type}", file=sys.stderr)
except urllib.error.URLError as e:
    print(f"[adapter] URLError: {e.reason} for {event_type}", file=sys.stderr)
PYEOF
}

# Main loop: poll all telemetry.jsonl files, track offsets, process new lines
echo "[adapter] watching $WATCH_DIR  ->  $API_URL"

while true; do
    while IFS= read -r -d '' tlog; do
        colony_id=$(basename "$(dirname "$(dirname "$tlog")")")
        offset_file="$STATE_DIR/$(echo "$tlog" | shasum -a 256 | cut -c1-16).offset"
        last_offset=0
        [[ -f "$offset_file" ]] && last_offset=$(cat "$offset_file")
        size=$(stat -f%z "$tlog" 2>/dev/null || stat -c%s "$tlog" 2>/dev/null || echo 0)

        if [[ "$size" -gt "$last_offset" ]]; then
            # Read new content from $last_offset onward
            tail -c "+$((last_offset + 1))" "$tlog" | while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                process_line "$colony_id" "$line"
            done
            echo "$size" > "$offset_file"
        fi
    done < <(find "$WATCH_DIR" -name 'telemetry.jsonl' -print0 2>/dev/null)

    sleep "$POLL_INTERVAL"
done
