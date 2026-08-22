#!/bin/bash
# Phase S close-out sweep (SPK-1900 wave) — 2026-08-21
set -u
cd /Users/zgbot/Desktop/ShopPilot
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PASS=0; FAIL=0

gate() {  # $1 = label, $2 = command
  OUT=$($2 2>&1)
  if echo "$OUT" | grep -qE ": PASS|verification: PASS|PASS —"; then
    echo "PASS  $1"; PASS=$((PASS+1))
  else
    echo "FAIL  $1"; echo "$OUT" | tail -3; FAIL=$((FAIL+1))
  fi
}

# New Phase S CLTs
gate "Verify1900a lithophane engine"      "./scripts/verify_locked.sh ShopPilotVerify1900a"
gate "Verify1900e image-to-relief engine" "./scripts/verify_locked.sh ShopPilotVerify1900e"
gate "Verify1900f nesting engine"         "./scripts/verify_locked.sh ShopPilotVerify1900f"
gate "Verify1900b frame/jog formatters"   "./scripts/verify_locked.sh ShopPilotVerify1900b"

# Structural gates
gate "gate 1900b frame+jog wiring" "python3 scripts/verify_1900b_frame_jog.py"
gate "gate 1900c beginner mode"    "python3 scripts/verify_1900c_mode.py"
gate "gate 1900f nesting wiring"   "python3 scripts/verify_1900f_nesting.py"
gate "gate 1900d dock audit"       "python3 scripts/verify_1900d_dock_audit.py"

# Regressions touching touched files
gate "regression Verify1206 preview fit" "./scripts/verify_locked.sh ShopPilotVerify1206"
gate "regression Verify1313 samples"     "./scripts/verify_locked.sh ShopPilotVerify1313"
gate "regression verify_1400b setup"     "python3 scripts/verify_1400b_setup.py"

# App build
OUT=$(./scripts/swift_locked.sh build --target ShopPilot 2>&1)
if echo "$OUT" | grep -q "Build of target: 'ShopPilot' complete"; then
  echo "PASS  app target build"; PASS=$((PASS+1))
else
  echo "FAIL  app target build"; echo "$OUT" | tail -3; FAIL=$((FAIL+1))
fi

echo
echo "Phase S sweep: $PASS PASS / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
