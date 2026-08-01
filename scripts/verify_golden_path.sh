#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "=== ShopPilot Golden Path Verify ==="
swift build --product ShopPilotGoldenPath
swift run ShopPilotGoldenPath
