#!/usr/bin/env bash
# Queen Protocol v2.14.0 — dispatch-lock auto-acquire from prompt-file path (§29.10).
#
# Real evidence (2026-05-09 19:11 vs 19:27): two queens in two tabs each
# dispatched X-test-repair (PID 33077 mine, 34795 the other). v2.13 ships
# dispatch-lock.sh, but it only protects when both queens call `acquire`
# explicitly. The other-tab queen ran `kimi-task.sh start --isolated`
# DIRECTLY, bypassing the lock. Adoption gap.
#
# This wrapper derives colony-id + shard-id from the prompt file path:
#
#   ~/.claude/state/colony/<colony-id>/shards/<shard-id>/prompt.md
#
# …and auto-invokes `dispatch-lock.sh acquire` before any backend spawn.
#
# Usage:
#   dispatch-lock-from-path.sh <prompt-file-path> [--queen <name>]
#
# Exit codes:
#   0 — lock acquired (or path doesn't match colony pattern → no-op)
#   1 — lock conflict (another queen holds it; refuses dispatch)
#   2 — config error
#
# Designed for kimi-task.sh / codex-task.sh / Agent-call wrapper integration.

set -euo pipefail

PROTO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCK_SCRIPT="${PROTO_DIR}/dispatch-lock.sh"

PROMPT_PATH="${1:-}"
shift || true
QUEEN="${$}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --queen) QUEEN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$PROMPT_PATH" ]]; then
    echo "usage: dispatch-lock-from-path.sh <prompt-file> [--queen <name>]" >&2
    exit 2
fi

# Resolve to absolute (so relative paths still match the regex)
ABS_PATH="$(cd "$(dirname "$PROMPT_PATH")" 2>/dev/null && pwd)/$(basename "$PROMPT_PATH")"

# Match the canonical colony shard prompt path
# /Users/<user>/.claude/state/colony/<colony-id>/shards/<shard-id>/prompt.md
RE='\.claude/state/colony/([^/]+)/shards/([^/]+)/prompt\.md$'
if [[ "$ABS_PATH" =~ $RE ]]; then
    COLONY_ID="${BASH_REMATCH[1]}"
    SHARD_ID="${BASH_REMATCH[2]}"
else
    # Path doesn't match colony pattern — ad-hoc dispatch, no lock needed
    echo "[lock-from-path] $ABS_PATH not in colony state — no-op (ad-hoc dispatch)"
    exit 0
fi

# Compute prompt-content hash for the lock holder (audit aid)
HASH=$(shasum -a 256 "$ABS_PATH" 2>/dev/null | cut -d' ' -f1 | head -c 16 || echo "")

# Acquire via the canonical lock script
if "$LOCK_SCRIPT" acquire "$COLONY_ID" "$SHARD_ID" --queen "$QUEEN" --prompt-hash "$HASH"; then
    exit 0
fi

echo "[lock-from-path] CONFLICT — refusing dispatch on $COLONY_ID/$SHARD_ID" >&2
echo "  Use 'dispatch-lock.sh check $COLONY_ID $SHARD_ID' to see the holder." >&2
echo "  Use 'dispatch-lock.sh release $COLONY_ID $SHARD_ID' if the holder is dead." >&2
exit 1
