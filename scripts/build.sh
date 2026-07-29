#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== ShopPilot Build ==="

# Verify Swift toolchain is available
if ! command -v swift &>/dev/null; then
    echo "ERROR: 'swift' not found in PATH. Install Xcode Command Line Tools or full Xcode." >&2
    exit 1
fi

echo "Swift version:"
swift --version | head -n1

# Clean previous build artifacts (optional — uncomment if always clean)
# swift package clean

echo ""
echo "Building..."
swift build

echo ""
echo "Build complete. Artifacts in .build/debug/"
