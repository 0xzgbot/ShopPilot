#!/usr/bin/env bash
# ShopPilot overnight shakedown harness (SPK-SHAKEc / SPK-SHAKEi).
#
# 1. Creates run dir /tmp/shoppilot-shake-YYYYMMDD-HHMM/
# 2. Runs the import-torture fixture gate (python3 scripts/verify_import_torture.py)
# 3. Discovers and runs ALL ShopPilotVerify* targets via verify_locked.sh (serialized,
#    exit codes + durations captured; never aborts the night on the first failure)
# 4. Optionally runs verify_golden* / verify_base_tier when present
# 5. Writes results/CLTS.md (target | PASS/FAIL | seconds | log path)
# 6. On FAIL, stages a MASTER_KANBAN bug card (repro + log path) and appends it once at
#    the end (single append; no mid-run board collisions).
#
# Usage:
#   ./scripts/run_overnight_shakedown.sh                 # full sweep
#   SHAKE_MAX_TARGET_SEC=600 ./scripts/run_overnight_shakedown.sh   # per-target cap
#   SHAKE_SKIP_TORTURE=1  ...                            # skip fixture gate
#
# Exit code: 0 = all green, 1 = one or more failures (cards staged).

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Xcode toolchain (xcode-select may point at CommandLineTools — see skill memory).
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

RUN_DIR="${SHAKE_RUN_DIR:-/tmp/shoppilot-shake-$(date +%Y%m%d-%H%M)}"
LOGS_DIR="$RUN_DIR/logs"
RESULTS_DIR="$REPO_ROOT/results"
MAX_TARGET_SEC="${SHAKE_MAX_TARGET_SEC:-900}"   # per-target watchdog (15 min default)
DATE_STAMP="$(date +%Y-%m-%d)"

mkdir -p "$LOGS_DIR" "$RESULTS_DIR"

PASS=0; FAIL=0; WARN=0; SKIP=0
FAILED_TARGETS=()
WARNED_TARGETS=()
: > "$RESULTS_DIR/CLTS.md"

log() { printf '%s\n' "$*"; }
log "ShopPilot overnight shakedown — $DATE_STAMP"
log "Run dir: $RUN_DIR"
log "Results: $RESULTS_DIR/CLTS.md"

# --- gate 0: import-torture fixtures --------------------------------------
if [[ "${SHAKE_SKIP_TORTURE:-0}" != "1" ]]; then
  log ""
  log "== [1/3] import-torture fixture gate =="
  T0=$(date +%s)
  python3 scripts/verify_import_torture.py > "$LOGS_DIR/import_torture.log" 2>&1
  RC=$?
  T1=$(date +%s)
  if [[ $RC -eq 0 ]]; then
    log "import_torture: PASS ($((T1-T0))s)"
    printf '| import-torture fixtures | PASS | %ds | %s |\n' "$((T1-T0))" "$LOGS_DIR/import_torture.log" >> "$RESULTS_DIR/CLTS.md"
    PASS=$((PASS+1))
  else
    log "import_torture: FAIL ($RC)"
    printf '| import-torture fixtures | FAIL | %ds | %s |\n' "$((T1-T0))" "$LOGS_DIR/import_torture.log" >> "$RESULTS_DIR/CLTS.md"
    FAIL=$((FAIL+1)); FAILED_TARGETS+=("import_torture")
  fi
else
  log "import_torture: SKIPPED (SHAKE_SKIP_TORTURE=1)"
fi

# --- discover targets -------------------------------------------------------
# Registration truth is Package.swift, not the filesystem (stale dirs exist).
TARGETS=()
while IFS= read -r t; do TARGETS+=("$t"); done < <(grep -oE 'ShopPilotVerify[0-9A-Za-z]+' Package.swift | sort -u)
log ""
log "== [2/3] CLT sweep: ${#TARGETS[@]} ShopPilotVerify* targets (serialized) =="

run_one() {
  local t="$1"
  local logfile="$LOGS_DIR/$t.log"
  local rc=0
  local start end elapsed
  start=$(date +%s)
  # Watchdog: run under a background pid, poll; kill if it exceeds the cap.
  ./scripts/verify_locked.sh "$t" > "$logfile" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s)
    if [[ $((now - start)) -gt $MAX_TARGET_SEC ]]; then
      log "  $t: TIMEOUT after ${MAX_TARGET_SEC}s — killing"
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      rc=124
      break
    fi
    sleep 5
  done
  if [[ $rc -ne 124 ]]; then
    wait "$pid" 2>/dev/null
    rc=$?
  fi
  end=$(date +%s)
  elapsed=$((end - start))
  echo "$rc" > "$logfile.exit"

  local verdict="FAIL"
  if [[ $rc -eq 0 ]]; then
    if grep -qiE ": PASS|verification: PASS|PASS —" "$logfile"; then
      verdict="PASS"
    else
      # Exit 0 but no PASS marker — the CLT convention is PASS print + exit 0.
      # Flag as WARN so we can eyeball it, but do not fail the night.
      verdict="WARN"
    fi
  fi

  printf '| %s | %s | %ss | %s |\n' "$t" "$verdict" "$elapsed" "$logfile" >> "$RESULTS_DIR/CLTS.md"
  log "  $t: $verdict (${elapsed}s, rc=$rc)"

  case "$verdict" in
    PASS) PASS=$((PASS+1)) ;;
    FAIL) FAIL=$((FAIL+1)); FAILED_TARGETS+=("$t") ;;
    WARN) WARN=$((WARN+1)); WARNED_TARGETS+=("$t") ;;
  esac
}

for t in "${TARGETS[@]}"; do
  run_one "$t"
done

# --- optional goldens / base-tier scripts -----------------------------------
log ""
log "== [3/3] optional script gates =="
for s in verify_golden_path.sh verify_base_tier.sh; do
  if [[ -x "scripts/$s" ]]; then
    T0=$(date +%s)
    bash "scripts/$s" > "$LOGS_DIR/$s.log" 2>&1
    RC=$?
    T1=$(date +%s)
    if [[ $RC -eq 0 ]]; then
      log "$s: PASS ($((T1-T0))s)"
      printf '| %s | PASS | %ds | %s |\n' "$s" "$((T1-T0))" "$LOGS_DIR/$s.log" >> "$RESULTS_DIR/CLTS.md"
      PASS=$((PASS+1))
    else
      log "$s: FAIL ($RC)"
      printf '| %s | FAIL | %ds | %s |\n' "$s" "$((T1-T0))" "$LOGS_DIR/$s.log" >> "$RESULTS_DIR/CLTS.md"
      FAIL=$((FAIL+1)); FAILED_TARGETS+=("$s")
    fi
  else
    log "$s: not present — skipping"
    SKIP=$((SKIP+1))
  fi
done

# --- summary ----------------------------------------------------------------
log ""
log "=============================================="
log "SWEEP SUMMARY — $PASS PASS, $FAIL FAIL, $WARN WARN, $SKIP skipped"
if [[ ${#WARNED_TARGETS[@]} -gt 0 ]]; then
  log "WARN (exit 0, no PASS marker — eyeball): ${WARNED_TARGETS[*]}"
fi
log "CLT table: $RESULTS_DIR/CLTS.md"
log "=============================================="

# --- stage kanban bug cards (one append at the end) -------------------------
CARD_FILE="$RUN_DIR/new_cards.md"
: > "$CARD_FILE"
if [[ ${#FAILED_TARGETS[@]} -gt 0 ]]; then
  {
    log ""
    log "### $DATE_STAMP — SHAKE sweep bug cards (Hermes coder, overnight shakedown)"
    log ""
    for t in "${FAILED_TARGETS[@]}"; do
      log "- [ ] **SPK-SHAKE-BUG-$t** **QA** Shakedown failure — \`$t\`"
      log "  - Repro: \`./scripts/verify_locked.sh $t\` (log: $LOGS_DIR/$t.log; exit \$(cat $LOGS_DIR/$t.log.exit 2>/dev/null))"
      log "  - AC: Engine+UI+Persist+Verify — diagnose root cause (product bug vs harness flake); fix or document; re-run target + nearest regressions green."
      log ""
    done
  } >> "$CARD_FILE"
  log "Staged $((${#FAILED_TARGETS[@]})) kanban card(s) at $CARD_FILE"
  cat "$CARD_FILE" >> "$REPO_ROOT/MASTER_KANBAN.md"
  log "Appended to MASTER_KANBAN.md — verify the section before committing."
else
  log "No failures — no kanban cards staged."
fi

if [[ $FAIL -gt 0 ]]; then
  log "SHAKE SWEEP: FAILURES PRESENT (${FAIL}) — see $RESULTS_DIR/CLTS.md"
  exit 1
fi
log "SHAKE SWEEP: ALL GREEN"
exit 0
