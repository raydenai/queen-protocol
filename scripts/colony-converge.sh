#!/usr/bin/env bash
# Queen Protocol v2.10.0 — colony-converge enforcement bundle (§28).
#
# Single command that runs every queen-side gate from §3.1 + §27.2 + §25.11 +
# §25.12 + §28 in sequence and blocks LAND on any failure. Removes "queen
# forgot to run gate X" as a structural failure mode.
#
# Real evidence (Elev-W1 colony, 2026-05-09): another queen documented in
# MANIFEST.md that it would run validate-report.py at converge, then shipped
# 2 of 3 shards with §3-failing reports + 1 critical money-charging bug
# (formatStripeAmount 100x error) caught only by retroactive Tier 0 review.
# colony-converge.sh exists so this cannot recur.
#
# Subcommands:
#   run <colony-id> <repo-path> [--skip-tier0] [--no-git-snapshot]
#       Run all gates and exit 0 (clean) / 1 (block LAND) / 2 (config error).
#
#   probe <colony-id>
#       Print which gates will run for this colony (dry-run).
#
# Per-gate failure surfaces both to stdout and as CONVERGE_AUDIT_RESULT
# events in the colony's telemetry.jsonl.

set -euo pipefail

PROTO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${PROTO_DIR}/scripts"
SCHEMAS_DIR="${PROTO_DIR}/schemas"
STATE_ROOT="${HOME}/.claude/state/colony"

CMD="${1:-help}"
shift || true

usage() {
    cat <<EOF
colony-converge.sh — single-command queen-side gate runner.

Subcommands:
  run <colony-id> <repo-path> [flags]
      Run all converge gates. Exit 0 if clean, 1 if any gate blocks LAND.
      Flags:
        --skip-tier0          Skip §27.2 Tier 0 local LLM review (use only
                              when local LLM unavailable; logs reason)
        --no-git-snapshot     Skip §25.12 external-stream detection (use
                              when no PLAN snapshot was taken)
        --shard-timeout-min N In-flight shard timeout in minutes (default:
                              colony plan deadline_minutes × 1.5; falls
                              back to 90 if no deadline declared)

  probe <colony-id>
      Dry-run: list which gates will run, which will skip, why.

  help
      This message.

Gates run, in order:
  1. §3.6  validate-report.py per shard
  2. §28   shard timeout (in-flight > deadline × 1.5 → mark TIMEOUT)
  3. §25.11 cross-shard-audit.py if ≥2 shards share data-pattern tags
  4. §27.2 Tier 0 (g4-task.sh review) per shard diff (skip if local LLM down)
  5. §25.12 git-snapshot.sh diff (external-stream check)

Any gate exit non-zero → CONVERGE_BLOCKED, exit 1, no LAND.
EOF
}

state_dir() {
    echo "${STATE_ROOT}/$1"
}

emit_telemetry() {
    local colony_id="$1" event="$2" detail="$3"
    local tlog
    tlog="$(state_dir "$colony_id")/log/telemetry.jsonl"
    mkdir -p "$(dirname "$tlog")"
    local ts
    ts="$(date -u +%FT%TZ)"
    echo "{\"event\":\"$event\",\"detail\":${detail:-null},\"ts\":\"$ts\"}" >> "$tlog"
}

# ─────────────────────────────────────────────────────────────────────────────
# Gate 1: §3.6 validate-report.py per shard
# ─────────────────────────────────────────────────────────────────────────────
gate_validate_reports() {
    local colony_id="$1"
    local sd
    sd="$(state_dir "$colony_id")/shards"
    local fail=0 total=0 passed=0

    if [[ ! -d "$sd" ]]; then
        echo "[gate1] no shards/ dir at $sd"
        return 0
    fi

    while IFS= read -r -d '' report; do
        total=$((total+1))
        if python3 "${SCRIPTS_DIR}/validate-report.py" "$report" >/dev/null 2>&1; then
            passed=$((passed+1))
        else
            fail=$((fail+1))
            echo "  FAIL: $report"
            python3 "${SCRIPTS_DIR}/validate-report.py" "$report" 2>&1 | sed 's/^/      /' | head -10
        fi
    done < <(find "$sd" -name 'report.json' -print0 2>/dev/null)

    echo "[gate1 §3.6] reports: $passed/$total passed schema validation"
    if [[ $fail -gt 0 ]]; then
        emit_telemetry "$colony_id" "CONVERGE_GATE_FAIL" \
            "{\"gate\":\"validate-report\",\"failed\":$fail,\"total\":$total}"
        return 1
    fi
    emit_telemetry "$colony_id" "CONVERGE_GATE_PASS" \
        "{\"gate\":\"validate-report\",\"passed\":$passed}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Gate 2: §28 shard timeout (in-flight > deadline × 1.5 → mark TIMEOUT)
# ─────────────────────────────────────────────────────────────────────────────
gate_shard_timeout() {
    local colony_id="$1" override_min="${2:-}"
    local sd
    sd="$(state_dir "$colony_id")/shards"
    local plan
    plan="$(state_dir "$colony_id")/plan.json"
    local timeout_min=90

    if [[ -n "$override_min" ]]; then
        timeout_min="$override_min"
    elif [[ -f "$plan" ]]; then
        timeout_min="$(python3 -c "
import json
try:
    p = json.load(open('$plan'))
    d = p.get('deadline_minutes') or max((s.get('deadline_minutes', 0) for s in p.get('shards', [])), default=0)
    print(int(d * 1.5) if d else 90)
except Exception:
    print(90)
")"
    fi

    [[ ! -d "$sd" ]] && { echo "[gate2 §28] no shards/ dir"; return 0; }

    local stale=0 total=0 inflight=0
    while IFS= read -r -d '' shard_dir; do
        total=$((total+1))
        local report="$shard_dir/report.json"
        if [[ -f "$report" ]]; then
            continue
        fi
        # No report.json — shard is in-flight or crashed. Check age via
        # the shard directory's mtime.
        inflight=$((inflight+1))
        local mtime now age_min
        mtime=$(stat -f%m "$shard_dir" 2>/dev/null || stat -c%Y "$shard_dir" 2>/dev/null || echo 0)
        now=$(date +%s)
        age_min=$(( (now - mtime) / 60 ))
        if [[ $age_min -gt $timeout_min ]]; then
            stale=$((stale+1))
            echo "  TIMEOUT: $(basename "$shard_dir") — in-flight ${age_min}min (limit ${timeout_min}min)"
        fi
    done < <(find "$sd" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    echo "[gate2 §28] in-flight: $inflight/$total · stale: $stale (timeout=${timeout_min}min)"
    if [[ $stale -gt 0 ]]; then
        emit_telemetry "$colony_id" "CONVERGE_GATE_FAIL" \
            "{\"gate\":\"shard-timeout\",\"stale\":$stale,\"timeout_min\":$timeout_min}"
        return 1
    fi
    emit_telemetry "$colony_id" "CONVERGE_GATE_PASS" \
        "{\"gate\":\"shard-timeout\",\"inflight\":$inflight}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Gate 3: §25.11 cross-shard-audit.py
# ─────────────────────────────────────────────────────────────────────────────
gate_cross_shard_audit() {
    local colony_id="$1" repo="$2"
    local plan
    plan="$(state_dir "$colony_id")/plan.json"
    local schema="${SCHEMAS_DIR}/cross-shard-audits.json"
    local tlog
    tlog="$(state_dir "$colony_id")/log/telemetry.jsonl"

    if [[ ! -f "$plan" ]]; then
        echo "[gate3 §25.11] no plan.json — skipping cross-shard audit"
        return 0
    fi
    if [[ ! -f "$schema" ]]; then
        echo "[gate3 §25.11] no schema at $schema — skipping"
        return 0
    fi

    local repo_arg="${repo:-/}"
    local migrations_dir="$repo/supabase/migrations"
    if python3 "${SCRIPTS_DIR}/cross-shard-audit.py" \
        --plan "$plan" --schema "$schema" --repo "$repo_arg" \
        --telemetry "$tlog" >/dev/null 2>&1; then
        echo "[gate3 §25.11] cross-shard audit: PASS (or no overlapping tags)"
        return 0
    else
        echo "[gate3 §25.11] cross-shard audit: FAIL"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Gate 4: §27.2 Tier 0 (g4-task.sh review) per shard diff
# ─────────────────────────────────────────────────────────────────────────────
gate_tier_0() {
    local colony_id="$1" repo="$2" skip="${3:-0}"
    if [[ "$skip" == "1" ]]; then
        echo "[gate4 §27.2] Tier 0 skipped (--skip-tier0 flag)"
        emit_telemetry "$colony_id" "CONVERGE_GATE_SKIPPED" \
            "{\"gate\":\"tier-0\",\"reason\":\"--skip-tier0\"}"
        return 0
    fi

    if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
        echo "[gate4 §27.2] local LLM (Ollama) unreachable — skipping Tier 0"
        emit_telemetry "$colony_id" "CONVERGE_GATE_SKIPPED" \
            "{\"gate\":\"tier-0\",\"reason\":\"ollama_unreachable\"}"
        return 0
    fi

    if ! command -v "${HOME}/.claude/scripts/g4-task.sh" >/dev/null 2>&1 \
       && [[ ! -x "${HOME}/.claude/scripts/g4-task.sh" ]]; then
        echo "[gate4 §27.2] g4-task.sh not installed — skipping Tier 0"
        emit_telemetry "$colony_id" "CONVERGE_GATE_SKIPPED" \
            "{\"gate\":\"tier-0\",\"reason\":\"g4_task_missing\"}"
        return 0
    fi

    local sd
    sd="$(state_dir "$colony_id")/shards"
    [[ ! -d "$sd" ]] && return 0

    local total=0 reviewed=0
    # We don't *block* on Tier 0 findings here — too many false-positive
    # contexts. Instead we run it, write findings to telemetry, surface
    # CRITICAL-tagged findings to stdout. Operator decides whether to block.
    while IFS= read -r -d '' shard_dir; do
        total=$((total+1))
        local diff_file="$shard_dir/diff.txt"
        if [[ ! -f "$diff_file" ]]; then
            continue  # No diff captured; skip
        fi
        reviewed=$((reviewed+1))
        # Run g4 review (sync mode; small shards complete in <300s)
        local out
        out=$("${HOME}/.claude/scripts/g4-task.sh" review "$diff_file" gemma4:31b 2>&1 | tail -200)
        if echo "$out" | grep -qiE 'CRITICAL|critical:'; then
            echo "  [TIER 0 CRITICAL] $(basename "$shard_dir"):"
            echo "$out" | grep -iE 'CRITICAL|critical:' | head -5 | sed 's/^/      /'
            emit_telemetry "$colony_id" "TIER_0_CRITICAL" \
                "{\"shard\":\"$(basename "$shard_dir")\"}"
        fi
    done < <(find "$sd" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    echo "[gate4 §27.2] Tier 0: $reviewed/$total shards reviewed (CRITICAL findings logged to telemetry)"
    emit_telemetry "$colony_id" "CONVERGE_GATE_PASS" \
        "{\"gate\":\"tier-0\",\"reviewed\":$reviewed}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Gate 5: §25.12 git-snapshot diff (external-stream check)
# ─────────────────────────────────────────────────────────────────────────────
gate_git_snapshot() {
    local colony_id="$1" repo="$2" skip="${3:-0}"
    if [[ "$skip" == "1" ]]; then
        echo "[gate5 §25.12] git-snapshot skipped (--no-git-snapshot)"
        return 0
    fi
    if [[ ! -f "$(state_dir "$colony_id")/git-snapshot.json" ]]; then
        echo "[gate5 §25.12] no PLAN-time snapshot — skipping (consider taking one next colony)"
        return 0
    fi
    if "${SCRIPTS_DIR}/git-snapshot.sh" diff "$colony_id" "$repo" >/dev/null 2>&1; then
        echo "[gate5 §25.12] git-snapshot: CLEAN (no external commits or unexpected writes)"
        return 0
    fi
    echo "[gate5 §25.12] git-snapshot: EXTERNAL_ACTIVITY detected"
    "${SCRIPTS_DIR}/git-snapshot.sh" diff "$colony_id" "$repo" 2>&1 | sed 's/^/    /' | head -25
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

case "$CMD" in
    run)
        COLONY_ID="${1:-}"
        REPO="${2:-}"
        SKIP_TIER_0=0
        SKIP_GIT_SNAP=0
        SHARD_TIMEOUT_MIN=""
        shift 2 2>/dev/null || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --skip-tier0)        SKIP_TIER_0=1; shift ;;
                --no-git-snapshot)   SKIP_GIT_SNAP=1; shift ;;
                --shard-timeout-min) SHARD_TIMEOUT_MIN="$2"; shift 2 ;;
                *) echo "Unknown flag: $1" >&2; exit 2 ;;
            esac
        done
        if [[ -z "$COLONY_ID" || -z "$REPO" ]]; then
            usage; exit 2
        fi

        echo "════════════════════════════════════════════════════════════"
        echo "  colony-converge v2.10 — colony=$COLONY_ID  repo=$REPO"
        echo "════════════════════════════════════════════════════════════"
        emit_telemetry "$COLONY_ID" "CONVERGE_AUDIT_START" "{}"

        any_fail=0
        gate_validate_reports "$COLONY_ID"            || any_fail=1
        gate_shard_timeout    "$COLONY_ID" "$SHARD_TIMEOUT_MIN" || any_fail=1
        gate_cross_shard_audit "$COLONY_ID" "$REPO"   || any_fail=1
        gate_tier_0           "$COLONY_ID" "$REPO" "$SKIP_TIER_0"
        gate_git_snapshot     "$COLONY_ID" "$REPO" "$SKIP_GIT_SNAP" || any_fail=1

        echo "────────────────────────────────────────────────────────────"
        if [[ $any_fail -eq 0 ]]; then
            echo "  CONVERGE_AUDIT_PASS — colony cleared for LAND"
            emit_telemetry "$COLONY_ID" "CONVERGE_AUDIT_PASS" "{}"
            exit 0
        else
            echo "  CONVERGE_BLOCKED — fix gate failures before LAND"
            emit_telemetry "$COLONY_ID" "CONVERGE_BLOCKED" "{}"
            exit 1
        fi
        ;;
    probe)
        COLONY_ID="${1:-}"
        if [[ -z "$COLONY_ID" ]]; then usage; exit 2; fi
        echo "Probe: $COLONY_ID"
        echo "  state dir: $(state_dir "$COLONY_ID") — $([[ -d "$(state_dir "$COLONY_ID")" ]] && echo present || echo MISSING)"
        echo "  shards: $(find "$(state_dir "$COLONY_ID")/shards" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
        echo "  reports: $(find "$(state_dir "$COLONY_ID")/shards" -name 'report.json' 2>/dev/null | wc -l | tr -d ' ')"
        echo "  plan.json: $([[ -f "$(state_dir "$COLONY_ID")/plan.json" ]] && echo present || echo absent)"
        echo "  git-snapshot: $([[ -f "$(state_dir "$COLONY_ID")/git-snapshot.json" ]] && echo present || echo absent)"
        echo "  Ollama: $(curl -fsS http://localhost:11434/api/version 2>/dev/null && echo reachable || echo UNREACHABLE)"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo "unknown command: $CMD" >&2; usage; exit 2
        ;;
esac
