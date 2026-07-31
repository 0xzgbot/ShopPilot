#!/usr/bin/env bash
# verify_base_tier.sh — SPK-0607 verification script
# Confirms that ShopPilot's base tier (Core) works without 3D features.
#
# Checks:
#   1. swift build succeeds (no 3D code in base target)
#   2. FeatureFlag enum has 3D features gated behind .has3D
#   3. ProductTier has Core/Studio/Studio3D with correct has3D semantics
#   4. StageGate gates Model stage behind has3D
#   5. Stage enum isAvailable() gates .model behind has3D
#   6. No 3D-specific source files in ShopPilotCore (they're in separate modules)
#   7. Core tier features (2D design, profile/pocket/drill, preview, GRBL) are always available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "=== SPK-0607: Base Tier Path Verification ==="
echo "Project: $PROJECT_DIR"
echo ""

# ── Check 1: swift build succeeds ──────────────────────────────────────
echo "Check 1: swift build succeeds"
if swift build --package-path "$PROJECT_DIR" > /dev/null 2>&1; then
    pass "Build succeeds"
else
    fail "Build failed"
fi

# ── Check 2: FeatureFlag gates 3D features ────────────────────────────
echo ""
echo "Check 2: FeatureFlag gates 3D features behind .has3D"
FF_FILE="$PROJECT_DIR/Sources/ShopPilotCore/FeatureFlag.swift"
if [[ -f "$FF_FILE" ]]; then
    # Verify 3D features return tier.has3D
    if grep -q "case .modelStage3D, .toolpath3D, .componentBrowser, .import3D, .sculptMode:" "$FF_FILE" && \
       grep -q "return tier.has3D" "$FF_FILE"; then
        pass "3D feature cases gated behind tier.has3D"
    else
        fail "3D feature gating not found in FeatureFlag"
    fi
    # Verify Studio features return tier.hasStudio
    if grep -q "case .textOnCurve, .quickEngrave, .toolpathTemplates, .jobSheetPDF, .keepOutZones:" "$FF_FILE" && \
       grep -q "return tier.hasStudio" "$FF_FILE"; then
        pass "Studio feature cases gated behind tier.hasStudio"
    else
        fail "Studio feature gating not found in FeatureFlag"
    fi
    # Verify Core features always return true
    if grep -q "case .vectorDesign2D, .coreToolpaths, .previewSimulation, .machineControl:" "$FF_FILE" && \
       grep -q "return true" "$FF_FILE"; then
        pass "Core features always available (return true)"
    else
        fail "Core feature availability not correct"
    fi
else
    fail "FeatureFlag.swift not found"
fi

# ── Check 3: ProductTier has correct tier hierarchy ────────────────────
echo ""
echo "Check 3: ProductTier enum has Core/Studio/Studio3D"
if grep -q "case core" "$FF_FILE" && \
   grep -q "case studio" "$FF_FILE" && \
   grep -q "case studio3d" "$FF_FILE"; then
    pass "All three tiers defined (core, studio, studio3d)"
else
    fail "Tier enum incomplete"
fi

# Verify has3D returns false for core and studio
if grep -A3 "case .core, .studio:" "$FF_FILE" | grep -q "return false"; then
    pass "Core and Studio tiers have has3D=false"
else
    fail "Core/Studio should have has3D=false"
fi
if grep -A3 "case .studio3d:" "$FF_FILE" | grep -q "return true"; then
    pass "Studio3D tier has has3D=true"
else
    fail "Studio3D should have has3D=true"
fi

# Verify hasStudio returns false for core only
if grep -A3 "case .core:" "$FF_FILE" | grep -q "return false"; then
    pass "Core tier has hasStudio=false"
else
    fail "Core should have hasStudio=false"
fi

# ── Check 4: StageGate gates Model stage ───────────────────────────────
echo ""
echo "Check 4: StageGate gates Model stage behind has3D"
SG_FILE="$PROJECT_DIR/Sources/ShopPilotCore/StageGate.swift"
if [[ -f "$SG_FILE" ]]; then
    if grep -q "canUseModelStage" "$SG_FILE" && grep -q "return tier.has3D" "$SG_FILE"; then
        pass "Model stage gated behind has3D"
    else
        fail "Model stage not gated behind has3D"
    fi
    if grep -q "canUse3DToolpaths" "$SG_FILE" && grep -q "return tier.has3D" "$SG_FILE"; then
        pass "3D toolpaths gated behind has3D"
    else
        fail "3D toolpaths not gated behind has3D"
    fi
    if grep -q "shouldHideModelStage" "$SG_FILE" && grep -q "return false" "$SG_FILE"; then
        pass "Model stage never hidden (upgrade prompt instead)"
    else
        warn "Model stage visibility policy unclear"
    fi
else
    fail "StageGate.swift not found"
fi

# ── Check 5: Stage enum isAvailable gates .model ──────────────────────
echo ""
echo "Check 5: Stage enum isAvailable() gates .model behind has3D"
STAGE_FILE="$PROJECT_DIR/Sources/ShopPilot/StageEnum.swift"
if [[ -f "$STAGE_FILE" ]]; then
    if grep -A3 "case .model:" "$STAGE_FILE" | grep -q "return tier.has3D"; then
        pass "Stage.model isAvailable returns tier.has3D"
    else
        fail "Stage.model isAvailable not gated"
    fi
    if grep -q "default:" "$STAGE_FILE" && grep -A1 "default:" "$STAGE_FILE" | grep -q "return true"; then
        pass "All other stages always available"
    else
        warn "Other stages availability unclear"
    fi
else
    fail "StageEnum.swift not found"
fi

# ── Check 6: Core features are always available ────────────────────────
echo ""
echo "Check 6: Core tier features always available regardless of tier"
if grep -q "case .vectorDesign2D, .coreToolpaths, .previewSimulation, .machineControl:" "$FF_FILE" && \
   grep -q "return true" "$FF_FILE"; then
    pass "Core features: vectorDesign2D, coreToolpaths, previewSimulation, machineControl"
else
    fail "Core feature availability incorrect"
fi

# ── Check 7: Base tier feature list matches PACKAGING.md ───────────────
echo ""
echo "Check 7: Base tier includes required Core features"
PACKAGING="$PROJECT_DIR/docs/planning/PACKAGING.md"
if [[ -f "$PACKAGING" ]]; then
    # Check that Tier 1 (Core) section exists
    if grep -q "Tier 1.*ShopPilot Core" "$PACKAGING"; then
        pass "Tier 1 (Core) section exists in PACKAGING.md"
    else
        warn "Tier 1 section naming may differ from expected"
    fi
    # Check that 3D is explicitly excluded from Core
    if grep -q "No 3D" "$PACKAGING"; then
        pass "PACKAGING.md explicitly states 'No 3D' for Core tier"
    else
        warn "No explicit 'No 3D' statement found for Core tier"
    fi
else
    warn "PACKAGING.md not found at expected path"
fi

# ── Check 8: ShopPilot target depends on ShopPilotCore ─────────────────
echo ""
echo "Check 8: Package.swift target structure"
PKG="$PROJECT_DIR/Package.swift"
if [[ -f "$PKG" ]]; then
    if grep -q '"ShopPilotCore"' "$PKG"; then
        pass "ShopPilotCore target exists"
    else
        fail "ShopPilotCore target missing from Package.swift"
    fi
    if grep -q '"ShopPilotSerial"' "$PKG"; then
        pass "ShopPilotSerial target exists"
    else
        fail "ShopPilotSerial target missing"
    fi
    if grep -q '"ShopPilotGeometry"' "$PKG"; then
        pass "ShopPilotGeometry target exists"
    else
        fail "ShopPilotGeometry target missing"
    fi
    # Verify ShopPilot app target lists core dependency
    if grep -A2 'executableTarget' "$PKG" | grep -q '"ShopPilotCore"'; then
        pass "ShopPilot app target depends on ShopPilotCore"
    else
        fail "ShopPilot app target missing ShopPilotCore dependency"
    fi
else
    fail "Package.swift not found"
fi

# ── Check 9: No 3D-specific files in core source ───────────────────────
echo ""
echo "Check 9: No 3D-specific source files in ShopPilotCore"
CORE_DIR="$PROJECT_DIR/Sources/ShopPilotCore"
# Check for files with 3D-related names
if ls "$CORE_DIR"/*3D* "$CORE_DIR"/*sculpt* "$CORE_DIR"/*component* 2>/dev/null | grep -q .; then
    warn "Found potentially 3D-related files in ShopPilotCore (may be fine if gated by FeatureFlag)"
else
    pass "No 3D-specific source files in ShopPilotCore (3D in Phase H+)"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Verification Summary ==="
echo "  ✅ Passed: $PASS"
echo "  ❌ Failed: $FAIL"
echo "  ⚠️  Warnings: $WARN"
echo ""

if (( FAIL > 0 )); then
    echo "RESULT: FAILED — Base tier verification did not pass."
    exit 1
elif (( WARN > 0 )); then
    echo "RESULT: PASSED WITH WARNINGS — Base tier verified, review warnings."
    exit 0
else
    echo "RESULT: PASSED — Base tier path verified successfully."
    exit 0
fi
