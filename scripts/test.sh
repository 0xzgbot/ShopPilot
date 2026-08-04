#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== ShopPilot Tests ==="

# Verify Swift toolchain is available
if ! command -v swift &>/dev/null; then
    echo "ERROR: 'swift' not found in PATH. Install Xcode Command Line Tools or full Xcode." >&2
    exit 1
fi

echo "Swift version: $(swift --version | head -1)"

# Xcode-aware toolchain (SPK-1105): xcode-select may point at the CommandLine
# Tools even when full Xcode is installed — XCTest then fails to import and the
# suite silently degrades to a build-only smoke test. Prefer the real Xcode.
if [[ -d "/Applications/Xcode.app/Contents/Developer" && "$(xcode-select -p 2>/dev/null)" != "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "DEVELOPER_DIR -> $DEVELOPER_DIR (Xcode toolchain)"
fi

# Determine testing mode:
#   - If the test target builds (Xcode installed), use swift test.
#   - Otherwise fall back to a build-only smoke test.
XCTEST_AVAILABLE=false
if swift build --build-tests &>/dev/null; then
    # Building the test target proves XCTest is linkable on this toolchain
    # (a `swift -e 'import XCTest'` probe always fails — scripts can't link
    # the XCTest framework even when Xcode is present).
    XCTEST_AVAILABLE=true
fi

if [[ "$XCTEST_AVAILABLE" == "true" ]]; then
    echo ""
    echo "Running XCTest suite..."
    echo "---"

    # Run tests with --parallel for speed; capture output for reporting.
    TEST_OUTPUT=$(swift test --parallel 2>&1) || {
        TEST_EXIT=$?
        echo "$TEST_OUTPUT"
        echo "---"
        echo "FAIL: swift test exited with code $TEST_EXIT"
        echo "Tests complete: FAILED"
        exit "$TEST_EXIT"
    }

    echo "$TEST_OUTPUT"
    echo "---"

    # The --parallel reporter emits no "Executed N tests" line on an all-green
    # run — only "[n/total] Testing …" progress lines (failing runs add
    # "Test Case … failed" details). The exit code above is the verdict;
    # parse real counts for the report.
    TOTAL=$(echo "$TEST_OUTPUT" | grep -Eo "\[[0-9]+/[0-9]+\]" | sed -E 's/\[([0-9]+)\/[0-9]+\]/\1/' | sort -n | tail -1 || true)
    TOTAL=${TOTAL:-0}
    FAILED=$(echo "$TEST_OUTPUT" | grep -c "Test Case '-.*' failed" || true)
    PASSED=$(( TOTAL - FAILED ))

    echo ""
    echo "=== Test Summary ==="
    echo "Total test cases: $TOTAL"
    echo "Passed: $PASSED"
    echo "Failed: $FAILED"

    if [[ "$FAILED" -gt 0 ]]; then
        echo "RESULT: FAIL"
        exit 1
    else
        echo "RESULT: PASS"
        exit 0
    fi

else
    echo ""
    echo "XCTest not available (no Xcode installed)."
    echo "Running build-only smoke test..."
    echo "---"

    # Build without tests to avoid XCTest compilation failures in CLI-only env
    swift build 2>&1
    BUILD_EXIT=$?

    echo "---"
    if [[ $BUILD_EXIT -eq 0 ]]; then
        echo "RESULT: PASS (build-only smoke test — no XCTest runtime)"
        echo "NOTE: Install Xcode or Xcode Command Line Tools to run full test suite."
    else
        echo "RESULT: FAIL (build failed)"
        exit $BUILD_EXIT
    fi
fi

echo ""
echo "Tests complete."
