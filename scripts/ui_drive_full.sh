#!/usr/bin/env bash
# =============================================================================
# ui_drive_full.sh — SPK-0623b comprehensive AX UI drive (ShopPilot, sim only)
#
# Walks every stage + File/Help/Preferences/Welcome/sheets to catch
# "no way to close a dialog / force-quit" bugs.
#
# Tools: ONLY scripts/ax_act.swift + scripts/capture_window.swift
#        (no cliclick, no osascript click-at, no live serial).
#
# Exit codes:
#   0  PASS
#   1  generic (app died)
#   2  ShopPilot binary not built (prints swift_locked recipe; does not compile)
#   3  NOT FOUND (a catalog control missing)
#   4  AX denied — STOP (never fake PASS)
#   5  DIALOG STUCK — AX found no dismiss (Cancel/Done/Close/Esc-equivalent)
#
# After a non-fatal fail the walk LOGS and CONTINUES. Worst code wins at exit.
# AX denied (4) always stops immediately.
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AX_ACT="$SCRIPT_DIR/ax_act.swift"
CAPTURE="$SCRIPT_DIR/capture_window.swift"
SWIFT="${SWIFT:-swift}"
PYTHON="${PYTHON:-python3}"
SHOTS_PREFIX="/tmp/shoppilot-ui-drive-full"
DUMP_DIR="/tmp/shoppilot-ui-drive-full-dumps"
APP_LOG="$SHOTS_PREFIX-app.log"
STEP_N=0
WORST_RC=0
STUCK=0
NOTFOUND=0

APP_BIN=""
LAUNCHED=0
APP_PID=""
ax_out=""
ax_rc=0

note() { printf '%s\n' "$*"; }

record_rc() {
    local rc="$1"
    [ "$rc" -gt "$WORST_RC" ] && WORST_RC="$rc"
    [ "$rc" = 5 ] && STUCK=1
    [ "$rc" = 3 ] && NOTFOUND=1
}

die() {
    local rc="$1"; shift
    printf 'FAIL [%s]: %s\n' "$rc" "$*" >&2
    if [ "$rc" = "4" ]; then
        printf '%s\n' \
            "TCC hint: System Settings → Privacy & Security → Accessibility" \
            "  enable Terminal / Hermes / Cursor (the process that runs this script)," \
            "  then RELAUNCH that app and re-run. Do not fake a PASS while AX is denied." \
            "  Screen Recording is needed for screenshots only." >&2
    fi
    exit "$rc"
}

ax() {
    # Hard 25s cap per ax_act call — a deadlocked AX query (e.g. the Services
    # submenu's dead "File Activity" service) must never wedge the walk.
    ax_out="$("$PYTHON" -c '
import subprocess, sys
try:
    r = subprocess.run(sys.argv[1:], capture_output=True, timeout=25)
    sys.stdout.buffer.write((r.stdout or b"") + (r.stderr or b""))
    sys.exit(r.returncode)
except subprocess.TimeoutExpired as e:
    if e.stdout:
        sys.stdout.buffer.write(e.stdout)
    sys.exit(124)
' "$SWIFT" "$AX_ACT" "$APP_PID" "$@" 2>&1)"
    ax_rc=$?
}

dump_save() {
    local tag="$1"
    mkdir -p "$DUMP_DIR"
    ax dump 7
    if [ "$ax_rc" -eq 1 ] && printf '%s' "$ax_out" | grep -q 'AX denied'; then
        printf '%s\n' "$ax_out" > "$DUMP_DIR/${tag}.txt"
        die 4 "AX denied — dump: $DUMP_DIR/${tag}.txt"
    fi
    printf '%s\n' "$ax_out" > "$DUMP_DIR/${tag}.txt"
    note "    dump: $DUMP_DIR/${tag}.txt"
}

# --- press ------------------------------------------------------------------
press_attempt() {
    local target="$1" scope="${2:-}" role="${3:-}" coords px py w h cx cy
    # Default to window scope: the menu bar (Services submenu) can deadlock
    # the app's AX handler — only menu-targeted steps opt into scope=menu.
    [ -z "$scope" ] && scope="window"
    if [ -n "$role" ]; then
        ax press "$target" "$scope" "$role"
    else
        ax press "$target" "$scope"
    fi
    case "$ax_rc" in
        124) die 1 "ax_act hung >25s on \"$target\"" ;;
        0)
            if printf '%s' "$ax_out" | grep -q '^PRESSED$'; then return 0; fi
            if printf '%s' "$ax_out" | grep -q '^PRESS FAILED'; then
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
        3) return 2 ;;
        1) printf '%s' "$ax_out" | grep -q 'AX denied' && return 4
           printf '%s' "$ax_out" | grep -q 'no windows' && return 3
           die 1 "ax_act tool failure: $(printf '%s' "$ax_out" | head -1)" ;;
        *) return 3 ;;
    esac
}

press_once() {
    local r
    press_attempt "$1"; r=$?
    [ "$r" = 4 ] && die 4 "AX denied while pressing \"$1\""
    return "$r"
}

# press_step: poll; on miss record 3 and continue (unless AX denied).
press_step() {
    local label="$1" primary="$2" fb="${3:-}" scope="${4:-}" role="${5:-}" i r
    note "  [$label] press \"$primary\"${fb:+ (fallback \"$fb\")}"
    for i in $(seq 1 6); do
        press_attempt "$primary" "$scope" "$role"; r=$?
        [ "$r" = 0 ] && note "    ok" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while pressing \"$primary\""
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during \"$label\" — log: $APP_LOG"
        if [ -n "$fb" ]; then
            press_attempt "$fb" "$scope" "$role"; r=$?
            [ "$r" = 0 ] && note "    ok (fallback \"$fb\")" && return 0
            [ "$r" = 4 ] && die 4 "AX denied while pressing \"$fb\""
            kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during \"$label\" — log: $APP_LOG"
        fi
        sleep 0.8
    done
    note "    FAIL [3] NOT FOUND: $label — last ax_act: $(printf '%s' "$ax_out" | tail -1) — dump $DUMP_DIR/last.txt"
    dump_save "miss-${label// /_}"
    record_rc 3
    return 3
}

# Top-level menu bar item (File / Help / ShopPilot) — role-scoped so the
# Services submenu's "File Activity" item can never shadow the real menu.
# The app must be FRONTMOST for menu bar presses to actually open menus
# (AXPress on an inactive app's menu bar returns PRESSED but does nothing).
activate_app() {
    local i
    for i in 1 2 3 4; do
        ax activate
        sleep 1
        ax frontmost
        if [ "$ax_rc" = 0 ] && printf '%s' "$ax_out" | grep -q '^FRONTMOST$'; then
            return 0
        fi
    done
    note "    (activate: app not frontmost after retries — menu presses may not open menus)"
    return 1
}
press_menubar() {
    if ! activate_app; then
        note "    FAIL [3] (env: app not frontmost) menu \"$2\" skipped — menu bar needs a foreground session"
        record_rc 3
        return 3
    fi
    press_step "$1" "$2" "${3:-}" menu AXMenuBarItem
}
# Item inside an OPEN menu (New Job / Settings… / Safety Notice …) —
# menubar-scoped so window text like "Create New Job" can't shadow it.
press_menuitem() {
    if ! activate_app; then
        note "    FAIL [3] (env: app not frontmost) menu item \"$2\" skipped — menu bar needs a foreground session"
        record_rc 3
        return 3
    fi
    press_step "$1" "$2" "${3:-}" menu
}

press_sample() {
    local i r
    note '  [sample] "V-Carve Greeting" | "Try a sample"'
    for i in $(seq 1 6); do
        press_attempt "V-Carve Greeting"; r=$?
        [ "$r" = 0 ] && note "    ok (Welcome sample)" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while pressing sample"
        press_attempt "Try a sample"; r=$?
        [ "$r" = 0 ] && note "    ok (Design empty state)" && return 0
        [ "$r" = 4 ] && die 4 "AX denied"
        kill -0 "$APP_PID" 2>/dev/null || die 1 "app exited during sample — log: $APP_LOG"
        press_attempt "Design"; r=$?
        [ "$r" = 0 ] && sleep 1
        sleep 1
    done
    note "    FAIL [3] sample not found"
    dump_save "miss-sample"
    record_rc 3
    return 3
}

# Esc is not a CGEvent in ax_act — Cancel / Done / Close / Get Started /
# I Understand / Discard / Dismiss / window close button are Esc-equivalents.

dump_has_dismiss() {
    # Window-only (exclude the dump's menubar subtree — starts at "  AXMenuBar|").
    local win_part
    win_part="$(printf '%s\n' "$ax_out" | awk '/^  AXMenuBar\|/{exit} {print}')"
    printf '%s' "$win_part" | grep -qiE "t=(Cancel|Done|Close|Get Started|I Understand|Discard|Dismiss|OK)" && return 0
    printf '%s' "$win_part" | grep -qiE "d=(Cancel|Done|Close|Get Started|I Understand|Discard|Dismiss|OK|close)" && return 0
    # Native window close button with a NON-empty description
    printf '%s' "$win_part" | grep -qE 'close=d=[^|]' && return 0
    return 1
}

try_dismiss() {
    local needle r
    for needle in Cancel Done Close OK "Get Started" "I Understand" Discard Dismiss; do
        press_attempt "$needle"; r=$?
        [ "$r" = 0 ] && note "    dismissed via \"$needle\"" && return 0
        [ "$r" = 4 ] && die 4 "AX denied while dismissing"
    done
    return 1
}

# After opening a sheet/alert/panel: dump, require a dismiss control, press it.
# Never hang. Missing dismiss → record 5, save dump, continue if possible.
assert_dismiss() {
    local label="$1"
    local dump_tag="dismiss-${label// /_}"
    note "  [dismiss] $label — require Cancel/Done/Close/Esc-equivalent"
    sleep 0.6
    dump_save "$dump_tag"
    # No modal chrome at all → not stuck (nothing to close; the MAIN window's
    # own close button must never count — closing it would quit the walk).
    # Window-only: the dump's menubar section (menu items like "Safety Notice",
    # "Close") must never count as modal chrome. Menubar subtree starts at the
    # "  AXMenuBar|" element line (window tree precedes it in the dump).
    win_part="$(printf '%s\n' "$ax_out" | awk '/^  AXMenuBar\|/{exit} {print}')"
    if ! printf '%s' "$win_part" | grep -qE 'AXSheet|AXDialog|== windows: [2-9]|Import Design File|Safety Notice|Unit System|Keyboard Shortcuts'; then
        note "    no modal detected (ok)"
        return 0
    fi
    if dump_has_dismiss; then
        if try_dismiss; then
            sleep 0.4
            return 0
        fi
        note "    FAIL [5] DIALOG STUCK: $label — dismiss control listed but press failed (last ax_act: $(printf '%s' "$ax_out" | tail -1)) — $DUMP_DIR/${dump_tag}.txt"
        record_rc 5
        return 5
    fi
    note "    FAIL [5] DIALOG STUCK: $label — no Cancel/Done/Close/OK/Get Started/I Understand/Discard in AX — $DUMP_DIR/${dump_tag}.txt"
    record_rc 5
    return 5
}

# Close the Settings window via its traffic-light close button (the bug class:
# no Cancel/Done in the form). Finds the window whose title contains
# "Settings" (never the main window), presses its close button.
close_settings_window() {
    local i line idx=""
    for i in 1 2 3; do
        line="$(grep -m1 -- "-- window $i:" "$DUMP_DIR/09-preferences-open.txt")"
        [ -z "$line" ] && break
        if printf '%s' "$line" | grep -q 'Settings'; then idx="$i"; break; fi
    done
    [ -z "$idx" ] && return 1
    ax closewin "$idx"
    if [ "$ax_rc" -eq 0 ] && printf '%s' "$ax_out" | grep -q '^CLOSED$'; then
        note "    closed Settings window via closewin $idx"
        return 0
    fi
    return 1
}

shot() {
    local name="$1" out r
    out="$SHOTS_PREFIX-$name.png"
    r="$("$SWIFT" "$CAPTURE" "$APP_PID" "$out" 2>&1)"
    if [ -f "$out" ]; then
        note "    shot: $out"
    else
        note "    shot skipped ($name): $r"
    fi
}

print_walk() {
    cat <<'EOF'
Full press plan (AX substring → ax_act press). Simulator only. Never Serial.

  0.  launch ShopPilot (existing binary; do not compile in this script)
  1.  Welcome: "V-Carve Greeting" OR Design "Try a sample"  dismiss: sample load / "Get Started"
  2.  File menu: press "File" then "New Job" (if present)
  3.  File menu: "Open Job" if present → MUST dismiss panel (Cancel) — never hang
  4.  File menu: "Save" if present → MUST dismiss panel (Cancel)
  5.  Setup rail "Setup" → Disclosure "Advanced" open then close (press Advanced twice)
  6.  Design rail "Design" → tools Select, Rect, Circle, Line, Polyline
      empty CTAs: "Import Artwork" (open hub → Cancel) and/or "Try a sample"
  7.  Cut rail "Cut" → "Cut out", "Pocket", "Engrave", "More"
  8.  Preview rail "Preview"
  9.  Machine: "Continue to Machine" | "Send to Machine Stage" | rail "Machine"
      picker "Simulator" (never Serial) → "Connect"
      assert Hold + Reset chrome
 10.  Preferences: menu "Preferences" | "Preferences…" → CLOSE (Cancel / close / Done)
      THIS IS THE BUG CLASS — if no dismiss, FAIL 5, dump path, continue catalog
 11.  Help: "Safety Notice" if present → dismiss ("I Understand" — note: no Cancel in source)
 12.  Preflight "Confirm pre-flight checklist" | "I've checked all of these"
 13.  Run "Run job. Start cutting" | "Run Job" → Hold → Resume

After EVERY sheet/alert: assert dismiss path. Missing → exit 5 (recorded; walk continues).
AX denied → exit 4 immediately.
EOF
}

resolve_app() {
    if [ -n "${SHOPPILOT_APP:-}" ]; then
        if [ -d "$SHOPPILOT_APP/Contents" ]; then
            APP_BIN="$SHOPPILOT_APP/Contents/MacOS/ShopPilot"
        elif [ -x "$SHOPPILOT_APP" ]; then
            APP_BIN="$SHOPPILOT_APP"
        else
            die 2 "SHOPPILOT_APP is set but not found: $SHOPPILOT_APP"
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
        cat >&2 <<'EOM'
FAIL [2]: no ShopPilot binary found. This script does not compile (swift lock
may be held by another agent). Build in a separate terminal, then re-run:

  ./scripts/swift_locked.sh build --product ShopPilot

Or set SHOPPILOT_APP to an existing .app / Mach-O. Never rm -rf .build.
EOM
        exit 2
    fi
}

kill_existing_instances() {
    if pgrep -x ShopPilot >/dev/null 2>&1; then
        note "note: terminating existing ShopPilot instance(s) for a clean Welcome"
        pkill -x ShopPilot 2>/dev/null
        for _ in $(seq 1 12); do
            pgrep -x ShopPilot >/dev/null 2>&1 || return 0
            sleep 0.5
        done
        die 1 "could not terminate an existing ShopPilot instance — close it manually"
    fi
}

wait_for_window() {
    local i
    for i in $(seq 1 14); do
        ax dump 3
        if [ "$ax_rc" -eq 0 ] && printf '%s' "$ax_out" | grep -q '== windows: [1-9]'; then
            return 0
        fi
        if printf '%s' "$ax_out" | grep -q 'AX denied'; then
            die 4 "AX denied / no window (last: $(printf '%s' "$ax_out" | head -1))"
        fi
        if [ "$ax_rc" -ne 0 ] && ! printf '%s' "$ax_out" | grep -q 'no windows'; then
            die 1 "ax_act tool failure: $(printf '%s' "$ax_out" | head -1)"
        fi
        if ! kill -0 "$APP_PID" 2>/dev/null; then
            die 1 "app exited during launch — log: $APP_LOG"
        fi
        sleep 2
    done
    die 4 "AX denied / no window after ~28s — last dump: $(printf '%s' "$ax_out" | head -1)"
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
    note "== ShopPilot AX full driver — self-check (no GUI required) =="
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
    note "usage: scripts/ui_drive_full.sh [--self-check|-h]"
    note "  default       launch ShopPilot and walk the full catalog (needs Accessibility TCC)"
    note "  --self-check  print the press plan; no GUI"
    note "  exits: 0 PASS / 2 not built / 3 NOT FOUND / 4 AX denied / 5 DIALOG STUCK"
    exit 0
fi

# --- full walk --------------------------------------------------------------
note "== ShopPilot AX full driver (simulator only) =="
print_walk
mkdir -p "$DUMP_DIR"

resolve_app
kill_existing_instances

note "launching: $APP_BIN"
"$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID=$!
LAUNCHED=1
note "pid: $APP_PID"

wait_for_window
dump_save "00-launch"
shot "01-launch"

# Welcome / sample (also dismisses Welcome sheet)
press_sample
assert_dismiss "after-sample"
shot "02-sample"

# File menu — New (in-app, no panel)
press_menubar "File menu" "File"
press_menuitem "New Job" "New Job"
sleep 0.4

# Open → file panel MUST be dismissable
press_menubar "File menu (open)" "File"
if press_menuitem "Open Job…" "Open Job…" "Open a Job"; then
    note "  [open] Open Job… presented — must Cancel"
    sleep 0.8
    assert_dismiss "file-open-panel"
fi

# Save → panel MUST be dismissable
press_menubar "File menu (save)" "File"
if press_menuitem "Save" "Save" "Save As…"; then
    note "  [save] Save presented — must Cancel (do not write a file)"
    sleep 0.8
    assert_dismiss "file-save-panel"
else
    note "    Save menu item not found (ok if disabled)"
fi

# Setup + Advanced
press_step "rail Setup" "Setup"
shot "03-setup"
press_step "Advanced open" "Advanced"
sleep 0.5
dump_save "04-advanced-open"
press_step "Advanced close" "Advanced"
sleep 0.3

# Design tools + empty CTAs
press_step "rail Design" "Design"
press_step "tool Select" "Select"
press_step "tool Rect" "Rect"
press_step "tool Circle" "Circle"
press_step "tool Line" "Line"
press_step "tool Polyline" "Polyline"
press_attempt "Import Artwork"; r=$?
if [ "$r" = 0 ]; then
    note "  [import hub] opened — must Cancel"
    sleep 0.6
    assert_dismiss "import-hub"
elif [ "$r" = 4 ]; then
    die 4 "AX denied on Import Artwork"
fi
shot "05-design"

# Cut strategies
press_step "rail Cut" "Cut"
press_step "Cut out" "Cut out"
press_step "Pocket" "Pocket"
press_step "Engrave" "Engrave"
press_step "More menu" "More"
shot "06-cut"

# Preview
press_step "rail Preview" "Preview"
shot "07-preview"

# Machine sim
press_step "handoff Machine" "Continue to Machine" "Send to Machine Stage"
press_step "rail Machine" "Machine"
press_step "transport Simulator" "Simulator" "" window AXRadioButton
press_step "Connect" "Connect" "" window AXButton
note "  [chrome] assert Hold + Reset"
ax dump 7
printf '%s\n' "$ax_out" > "$DUMP_DIR/08-machine.txt"
ok=1
printf '%s' "$ax_out" | grep -qF "Hold. Pause machine motion now" || ok=0
printf '%s' "$ax_out" | grep -qF "Reset. Stop the machine and clear the controller" || ok=0
if [ "$ok" = 1 ]; then
    note "    ok Hold/Reset"
else
    note "    FAIL [3] Hold/Reset chrome missing — $DUMP_DIR/08-machine.txt"
    record_rc 3
fi
shot "08-machine"

# Preferences — THE BUG CLASS
note "  [prefs] open Preferences… then CLOSE (never leave Settings up)"
press_menubar "ShopPilot menu" "ShopPilot"
if ! press_menuitem "Preferences…" "Preferences…" "Settings…"; then
    note "    FAIL [3] Preferences menu item not found"
    record_rc 3
    dump_save "09-preferences-miss"
else
    sleep 1.2
    dump_save "09-preferences-open"
    shot "09-preferences"
    if close_settings_window; then
        sleep 0.6
        dump_save "10-preferences-after-close"
        if printf '%s' "$(cat "$DUMP_DIR/10-preferences-after-close.txt")" | grep -qiE 'Unit System|Keyboard Shortcuts|Skip beginner'; then
            note "    FAIL [5] DIALOG STUCK: Preferences still visible after close — $DUMP_DIR/10-preferences-after-close.txt"
            record_rc 5
        else
            note "    preferences closed"
        fi
    else
        note "    FAIL [5] DIALOG STUCK: no Settings window close button found — $DUMP_DIR/09-preferences-open.txt"
        record_rc 5
    fi
fi

# Help → Safety Notice (interactiveDismissDisabled; only "I Understand")
note "  [help] Safety Notice if present"
press_menubar "Help menu" "Help"
if press_menuitem "Safety Notice" "Safety Notice"; then
    sleep 0.6
    dump_save "11-safety"
    assert_dismiss "safety-notice"
else
    note "    Safety Notice not in AX (logged; continue)"
fi

# Preflight / run / hold / resume
press_step "preflight" "Confirm pre-flight checklist" "I've checked all of these"
press_step "Run" "Run job. Start cutting" "Run Job"
sleep 1
press_step "Hold" "Hold. Pause machine motion"
sleep 1
press_step "Resume" "Resume. Continue machine motion"
shot "11-final"
dump_save "12-final"

note ""
if [ "$WORST_RC" = 0 ]; then
    note "PASS — full AX catalog completed (Simulator only; never live serial)"
    exit 0
fi
note "DONE WITH FAILURES — worst exit $WORST_RC (NOTFOUND=$NOTFOUND STUCK=$STUCK)"
note "Dumps: $DUMP_DIR   shots: ${SHOTS_PREFIX}-*.png"
note "Do not treat force-quit as success. Do not mark SPK-0623 [x]."
exit "$WORST_RC"
