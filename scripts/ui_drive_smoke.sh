#!/usr/bin/env bash
# =============================================================================
# ui_drive_smoke.sh — SPK-0623a AX smoke driver (ShopPilot, simulator only)
#
# Drives the native ShopPilot app through the G1-style sim walk using ONLY the
# existing Accessibility tools scripts/ax_act.swift + scripts/capture_window.swift
# (no XCUITest, no cliclick, no computer-use, no new Swift).
#
# Walk (AX substrings from docs/planning/UI_AGENT_DRIVE.md, labels verified
# against Sources on 2026-08-13):
#   sample ("V-Carve Greeting" | "Try a sample") -> rail "Cut" -> "Cut out" ->
#   rail "Preview" -> "Continue to Machine" (| "Send to Machine Stage") ->
#   picker "Simulator" -> "Connect" -> assert Hold/Reset chrome ->
#   "Confirm pre-flight checklist" (| "I've checked all of these") ->
#   "Run job. Start cutting" (| "Run Job") -> "Hold. Pause machine motion" ->
#   "Resume. Continue machine motion"
#
# Screenshots: /tmp/shoppilot-ui-drive-*.png (best-effort; need Screen
# Recording TCC). AX tree dump: /tmp/shoppilot-ui-drive-00-ax-dump.txt.
#
# Exit codes:
#   0  PASS — the whole walk completed
#   1  generic failure (app died / press failed / existing instance stuck)
#   3  NOT FOUND — app binary, helper script, or a walk control missing
#   4  AX denied (Accessibility TCC) — prints the hint, NEVER fakes PASS
#
# Safety: never selects Serial / a real port (Simulator transport only),
# never rm -rf .build, never builds (launches an existing binary; build with
# ./scripts/swift_locked.sh build --product ShopPilot if missing).
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AX_ACT="$SCRIPT_DIR/ax_act.swift"
CAPTURE="$SCRIPT_DIR/capture_window.swift"
# SPK-DOGFOOD-05 — prefer a precompiled ax_act binary: the JIT-interpreted
# script SIGILLs on deep AX trees (depth >= 7). Build once with:
#   swiftc -O -o "$SCRIPT_DIR/.ax_act_bin" "$SCRIPT_DIR/ax_act.swift"
AX_BIN="$SCRIPT_DIR/.ax_act_bin"
if [ -x "$AX_BIN" ]; then SWIFT=""; AX_RUN() { "$AX_BIN" "$@"; }; else AX_RUN() { "$SWIFT" "$AX_ACT" "$@"; }; fi
SHOTS_PREFIX="/tmp/shoppilot-ui-drive"
DUMP_LOG="$SHOTS_PREFIX-00-ax-dump.txt"
APP_LOG="$SHOTS_PREFIX-app.log"

APP_BIN=""
LAUNCHED=0
APP_PID=""
ax_out=""
ax_rc=0

# --- tiny helpers -----------------------------------------------------------
note() { printf '%s\n' "$*"; }

die() { # <exit_code> <message...>
    local rc="$1"; shift
    printf 'FAIL [%s]: %s\n' "$rc" "$*" >&2
    if [ "$rc" = "4" ]; then
        printf '%s\n' \
            "TCC hint: grant Accessibility (and Screen Recording for screenshots) to the process that runs this script:" \
            "  System Settings → Privacy & Security → Accessibility → enable Terminal/Hermes (and Screen Recording for shots)," \
            "  then RELAUNCH that app and re-run. Do not fake a PASS while AX is denied." >&2
    fi
    exit "$rc"
}

ax() { # <args...> — run ax_act.swift against APP_PID; output -> ax_out, rc -> ax_rc
    ax_out="$(AX_RUN "$APP_PID" "$@" 2>&1)"
    ax_rc=$?
}

# --- press helpers ----------------------------------------------------------
# press_attempt <target> — one press try. Returns:
#   0 pressed, 2 NOT FOUND, 3 found-but-press-failed, 4 AX denied / no windows
press_attempt() {
    local target="$1" coords px py w h cx cy
    ax press "$target"
    case "$ax_rc" in
        0)
            if printf '%s' "$ax_out" | grep -q '^PRESSED$'; then return 0; fi
            if printf '%s' "$ax_out" | grep -q '^PRESS FAILED'; then
                # Last-resort: presspos at the matched element's top-left inset
                # (lands on the control, not a bare static-text child).
                coords="$(printf '%s\n' "$ax_out" \
                    | sed -n 's/.*|p=\([0-9][0-9]*\),\([0-9][0-9]*\)|s=\([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1 \2 \3 \4/p' \
                    | head -1)"
                if [ -n "$coords" ]; then
                    read -r px py w h <<< "$coords"
                    cx=$((px + 2)); cy=$((py + 2))
                    ax presspos "$cx" "$cy"
                    if [ "$ax_rc" -eq 0 ] && printf '%s' "$ax_out" | grep -q '^PRESSED$'; then
                        note "      (presspos fallback worked)"
                        return 0
                    fi
                fi
                return 3
            fi
            return 3
            ;;
        3) return 2 ;;                                  # NOT FOUND
        1) printf '%s' "$ax_out" | grep -q 'AX denied' && return 4; return 3 ;;
        *) return 3 ;;
    esac
}

# Sample step: Welcome-sheet sample card, or the Design empty-state
# "Try a sample" (needs the Design rail pressed first on non-first runs,
# where the Welcome sheet does not auto-appear).
press_sample() {
    local i r
    note '  [sample] press "V-Carve Greeting" (fallback: Design empty-state "Try a sample")'
    for i in $(seq 1 6); do
        r="$(press_attempt "V-Carve Greeting")"
        [ "$r" = 0 ] && note "    ok (Welcome sample)" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while pressing sample"
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during sample step — log: $APP_LOG"
        r="$(press_attempt "Try a sample")"
        [ "$r" = 0 ] && note "    ok (Design empty state)" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while pressing sample"
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during sample step — log: $APP_LOG"
        # Not visible yet: make sure we're on the Design stage (its empty
        # state shows "Try a sample"), then retry.
        r="$(press_attempt "Design")"
        [ "$r" = 0 ] && sleep 1
        sleep 1
    done
    die 3 'NOT FOUND: sample (tried "V-Carve Greeting" and "Try a sample", incl. after switching to the Design stage) — see '"$DUMP_LOG"
}

# press_step <label> <primary> [fallback] — poll primary/fallback to PRESSED.
press_step() {
    local label="$1" primary="$2" fb="${3:-}" i r
    note "  [$label] press \"$primary\"${fb:+ (fallback \"$fb\")}"
    for i in $(seq 1 8); do
        r="$(press_attempt "$primary")"
        [ "$r" = 0 ] && note "    ok" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while pressing \"$primary\""
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during \"$label\" — log: $APP_LOG"
        if [ -n "$fb" ]; then
            r="$(press_attempt "$fb")"
            [ "$r" = 0 ] && note "    ok (fallback \"$fb\")" && return 0
            [ "$r" = 4 ] && die 4 "AX denied while pressing \"$fb\""
            kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during \"$label\" — log: $APP_LOG"
        fi
        sleep 1
    done
    die 3 "NOT FOUND: $label (tried \"$primary\"${fb:+ and \"$fb\"}) — see $DUMP_LOG"
}

# assert_dump_has <label> <needle...> — poll dumps until all needles present.
assert_dump_has() {
    local label="$1"; shift
    local i needle ok=1
    note "  [$label] assert visible: $*"
    for i in $(seq 1 8); do
        ax dump 7
        ok=1
        for needle in "$@"; do
            printf '%s' "$ax_out" | grep -qF -- "$needle" || { ok=0; break; }
        done
        [ "$ok" = 1 ] && note "    ok" && return 0
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during \"$label\" — log: $APP_LOG"
        sleep 1
    done
    die 3 "NOT FOUND: $label (missing: $*) — see $DUMP_LOG"
}

shot() { # <step-name> — best-effort window capture (needs Screen Recording TCC)
    local name="$1" out r
    out="$SHOTS_PREFIX-$name.png"
    r="$("$SWIFT" "$CAPTURE" "$APP_PID" "$out" 2>&1)"
    if [ -f "$out" ]; then
        note "    shot: $out"
    else
        note "    shot skipped ($name): $r — Screen Recording TCC not granted to this process?"
    fi
}

# --- walk list --------------------------------------------------------------
print_walk() {
    cat <<'EOF'
Press list (walk order, AX substring -> ax_act press):
   1. sample:     "V-Carve Greeting"            fallback "Try a sample"
   2. rail:       "Cut"
   3. generate:   "Cut out"
   4. rail:       "Preview"
   5. handoff:    "Continue to Machine"         fallback "Send to Machine Stage"
   6. transport:  "Simulator"  (segmented picker radio — never Serial)
   7. connect:    "Connect"
   8. assert:     "Hold. Pause machine motion" + "Reset. Stop and clear the machine" + "Idle"
   9. preflight:  "Confirm pre-flight checklist" fallback "I've checked all of these"
  10. run:        "Run job. Start cutting"      fallback "Run Job"
  11. hold:       "Hold. Pause machine motion"
  12. resume:     "Resume. Continue machine motion"
EOF
}

# --- app lifecycle ----------------------------------------------------------
resolve_app() {
    if [ -n "${SHOPPILOT_APP:-}" ]; then
        if [ -d "$SHOPPILOT_APP/Contents" ]; then
            APP_BIN="$SHOPPILOT_APP/Contents/MacOS/ShopPilot"
        elif [ -x "$SHOPPILOT_APP" ]; then
            APP_BIN="$SHOPPILOT_APP"
        else
            die 3 "SHOPPILOT_APP is set but not found: $SHOPPILOT_APP"
        fi
    else
        for c in \
            "$REPO_ROOT/.build/debug/ShopPilot" \
            "$REPO_ROOT/.build/arm64-apple-macosx/debug/ShopPilot" \
            "$REPO_ROOT/.build/x86_64-apple-macosx/debug/ShopPilot"; do
            [ -x "$c" ] && { APP_BIN="$c"; break; }
        done
        if [ -z "$APP_BIN" ] && [ -d "$REPO_ROOT/dist/ShopPilot.app" ]; then
            APP_BIN="$REPO_ROOT/dist/ShopPilot.app/Contents/MacOS/ShopPilot"
        fi
    fi
    if [ -z "$APP_BIN" ] || [ ! -x "$APP_BIN" ]; then
        die 3 "no ShopPilot binary found — build first with ./scripts/swift_locked.sh build --product ShopPilot, or set SHOPPILOT_APP"
    fi
}

kill_existing_instances() {
    if pgrep -x ShopPilot >/dev/null 2>&1; then
        note "note: terminating existing ShopPilot instance(s) so the walk starts from a clean Welcome/empty state"
        pkill -x ShopPilot 2>/dev/null
        for _ in $(seq 1 12); do
            pgrep -x ShopPilot >/dev/null 2>&1 || return 0
            sleep 0.5
        done
        die 1 "could not terminate an existing ShopPilot instance — close it manually and re-run"
    fi
}

wait_for_window() {
    local i
    for i in $(seq 1 14); do
        ax dump 3
        if [ "$ax_rc" -eq 0 ] && printf '%s' "$ax_out" | grep -q '== windows: [1-9]'; then
            return 0
        fi
        if ! kill -0 "$APP_PID" 2>/dev/null; then
            die 1 "app exited during launch — log: $APP_LOG"
        fi
        sleep 2
    done
    die 4 "AX denied / no window after ~28s — Accessibility TCC not granted to this process? (last dump: $(printf '%s' "$ax_out" | head -1))"
}

cleanup() {
    if [ "$LAUNCHED" = 1 ] && [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null
        sleep 1
        kill -0 "$APP_PID" 2>/dev/null && kill -9 "$APP_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

# --- modes ------------------------------------------------------------------
if [ "${1:-}" = "--self-check" ]; then
    note "== ShopPilot AX smoke driver — self-check (no GUI required) =="
    [ -f "$AX_ACT" ] || die 3 "missing helper: $AX_ACT"
    [ -f "$CAPTURE" ] || die 3 "missing helper: $CAPTURE"
    note "helpers present: scripts/ax_act.swift, scripts/capture_window.swift"
    note ""
    print_walk
    note ""
    note "self-check: OK"
    exit 0
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    note "usage: scripts/ui_drive_smoke.sh [--self-check|-h]"
    note "  (default) launch ShopPilot and drive the full AX sim walk; exit 0 PASS / 3 NOT FOUND / 4 AX denied"
    note "  --self-check  assert helpers exist + print the press list; no GUI"
    exit 0
fi

# --- full walk --------------------------------------------------------------
note "== ShopPilot AX smoke driver (simulator only) =="
print_walk

resolve_app
kill_existing_instances

note "launching: $APP_BIN"
"$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID=$!
LAUNCHED=1
note "pid: $APP_PID"

wait_for_window
note "window visible — AX dump -> $DUMP_LOG"
ax dump 7
printf '%s\n' "$ax_out" > "$DUMP_LOG"
note "  dump lines: $(wc -l < "$DUMP_LOG" | tr -d ' ')"
shot "01-launch"

press_sample
shot "02-sample-loaded"

press_step "rail to Cut stage" "Cut"
press_step "generate profile toolpath" "Cut out"
shot "03-cut-stage"

press_step "rail to Preview stage" "Preview"
shot "04-preview"

press_step "handoff to Machine" "Continue to Machine" "Send to Machine Stage"
press_step "transport picker = Simulator" "Simulator"
press_step "connect" "Connect"
assert_dump_has "safety chrome after Connect" \
    "Hold. Pause machine motion" "Reset. Stop and clear the machine" "Idle"
shot "05-machine-connected"

press_step "pre-flight checklist" "Confirm pre-flight checklist" "I've checked all of these"
press_step "start job" "Run job. Start cutting" "Run Job"
sleep 1
press_step "hold during run" "Hold. Pause machine motion"
sleep 1
press_step "resume" "Resume. Continue machine motion"
shot "06-final"

note ""
note "PASS — full AX smoke walk completed (Simulator only; never touched live serial)"
exit 0
