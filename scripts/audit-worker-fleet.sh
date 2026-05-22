#!/usr/bin/env bash
# audit-worker-fleet.sh — self-verifying lane-coverage check for the §29.18 matrix.
#
# Greps the actual `~/.claude/scripts/*-task.sh` files for the four helper
# patterns we care about and prints a live audit matrix. Replaces the
# hand-maintained markdown table in QUEEN_PROTOCOL.md §29.18 — that table
# will drift the moment any lane gets/loses a helper.
#
# Exit codes:
#   0 — all expected helpers present (per the lane-policy below)
#   1 — at least one expected helper is missing
#
# Lane policy (what each lane is expected to have):
#   Lane               is_*_alive  guard_data_sharing  dispatch-lock  health-ping
#   kimi-task.sh       required    required             required       required
#   codex-task.sh      N/A         required             required       required
#   gemini-task.sh     required    required             required       required
#   grok-task.sh       required    required             optional       required
#   grok-build-task.sh required    required             optional       required
#   jules-task.sh      N/A         required             optional       N/A
#   g4-task.sh         required    N/A                  optional       N/A
#
# "N/A" means structurally not applicable (e.g. local Ollama doesn't leak
# externally, codex-task.sh doesn't launch processes, jules runs server-side
# on Google VMs — no local PID to track).

set -euo pipefail

QUIET=0
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=1
  shift
fi

SCRIPT_DIR="${HOME}/.claude/scripts"
HEALTH_SCRIPT="${SCRIPT_DIR}/sidecar-health.sh"

# Lane configuration. Each entry: name|alive-policy|guard-policy|lock-policy|ping-policy
# Policy values: required | optional | na
LANES=(
  "kimi-task.sh|required|required|required|required"
  "codex-task.sh|na|required|required|required"
  "gemini-task.sh|required|required|required|required"
  "grok-task.sh|required|required|optional|required"
  "grok-build-task.sh|required|required|optional|required"
  "jules-task.sh|na|required|optional|na"
  "g4-task.sh|required|na|optional|na"
)

# Detection helpers — return "present" / "absent" by grepping the file.
detect_alive_helper() {
  local file="$1"
  if grep -qE '^is_[a-z0-9_]+_alive\(\)' "$file" 2>/dev/null; then
    # Also confirm the case-fix (lowercase tr) is in place — otherwise the
    # helper exists but has the v2.15.2 false-DONE bug.
    if grep -q "tr '\[:upper:\]' '\[:lower:\]'" "$file" 2>/dev/null; then
      echo "present"
    else
      echo "case-bug"
    fi
  else
    echo "absent"
  fi
}

detect_guard() {
  local file="$1"
  if grep -qE '^guard_data_sharing\(\)' "$file" 2>/dev/null; then
    echo "present"
  else
    echo "absent"
  fi
}

detect_lock_wiring() {
  local file="$1"
  if grep -qE 'dispatch-lock-from-path\.sh|acquire-lock' "$file" 2>/dev/null; then
    echo "present"
  else
    echo "absent"
  fi
}

detect_health_ping() {
  local lane_name="$1"
  # Map lane name → expected ping function name
  local fn
  case "$lane_name" in
    kimi-task.sh)        fn="ping_kimi" ;;
    codex-task.sh)       fn="ping_codex" ;;
    gemini-task.sh)      fn="ping_gemini" ;;
    grok-task.sh)        fn="ping_grok" ;;
    grok-build-task.sh)  fn="ping_grok_build" ;;
    jules-task.sh)       fn="ping_jules" ;;
    g4-task.sh)          fn="ping_g4" ;;
    *)                   fn="" ;;
  esac
  [[ -z "$fn" ]] && { echo "absent"; return; }
  if [[ -f "$HEALTH_SCRIPT" ]] && grep -qE "^${fn}\(\)" "$HEALTH_SCRIPT" 2>/dev/null; then
    echo "present"
  else
    echo "absent"
  fi
}

verdict_cell() {
  local detected="$1" policy="$2"
  case "$policy:$detected" in
    required:present)  echo "OK" ;;
    required:absent)   echo "MISSING" ;;
    required:case-bug) echo "CASE-BUG" ;;
    optional:present)  echo "OK" ;;
    optional:absent)   echo "(skip)" ;;
    optional:case-bug) echo "CASE-BUG" ;;
    na:*)              echo "N/A" ;;
    *)                 echo "?" ;;
  esac
}

is_failure() {
  case "$1" in
    MISSING|CASE-BUG) return 0 ;;
    *) return 1 ;;
  esac
}

# ── tabulate ──────────────────────────────────────────────────────────────────
report=""
failures=0
report+=$(printf "%-22s %-10s %-10s %-10s %-10s\n" "Lane" "is_alive" "ds_guard" "lock" "health")$'\n'
report+=$(printf "%-22s %-10s %-10s %-10s %-10s\n" "----" "--------" "--------" "----" "------")$'\n'

for entry in "${LANES[@]}"; do
  IFS='|' read -r lane alive_policy guard_policy lock_policy ping_policy <<<"$entry"
  file="${SCRIPT_DIR}/${lane}"

  if [[ ! -f "$file" ]]; then
    report+=$(printf "%-22s %s" "$lane" "MISSING (file not found)")$'\n'
    failures=$((failures+1))
    continue
  fi

  alive_state=$(detect_alive_helper "$file")
  guard_state=$(detect_guard "$file")
  lock_state=$(detect_lock_wiring "$file")
  ping_state=$(detect_health_ping "$lane")

  alive_cell=$(verdict_cell "$alive_state" "$alive_policy")
  guard_cell=$(verdict_cell "$guard_state" "$guard_policy")
  lock_cell=$(verdict_cell "$lock_state" "$lock_policy")
  ping_cell=$(verdict_cell "$ping_state" "$ping_policy")

  for c in "$alive_cell" "$guard_cell" "$lock_cell" "$ping_cell"; do
    is_failure "$c" && failures=$((failures+1))
  done

  report+=$(printf "%-22s %-10s %-10s %-10s %-10s" \
    "$lane" "$alive_cell" "$guard_cell" "$lock_cell" "$ping_cell")$'\n'
done

# ── emit ──────────────────────────────────────────────────────────────────────
if [[ $QUIET -eq 1 ]]; then
  # SessionStart-friendly output: silent on green, single line on red.
  if [[ $failures -gt 0 ]]; then
    echo "Queen Protocol §29.18 worker-fleet audit: $failures gap(s). Run: ~/projects/queen-protocol/scripts/audit-worker-fleet.sh" >&2
    exit 1
  fi
  exit 0
fi

printf "Queen Protocol §29.18 audit — worker-fleet helper coverage\n"
printf "%s (UTC)\n\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf "%s" "$report"

printf "\nLegend: OK=present | MISSING=required-but-absent | CASE-BUG=present-but-missing-lowercase-fix | (skip)=optional-absent | N/A=structurally-inapplicable\n"

if [[ $failures -gt 0 ]]; then
  printf "\nVERDICT: %d gap(s) found. See §29.18 in QUEEN_PROTOCOL.md.\n" "$failures" >&2
  exit 1
fi

printf "\nVERDICT: all required helpers present across the fleet.\n"
exit 0
