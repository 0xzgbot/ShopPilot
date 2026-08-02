#!/usr/bin/env python3
"""SPK-1100 verification without XCTest (works on Command Line Tools only).

Runs: swift run ShopPilotVerify1100
Covers .shoppilot package round-trip for vectors + toolpaths + document variables.
"""
import subprocess
import sys

print("SPK-1100 — Document session spine verification")
print("Running: swift run ShopPilotVerify1100")
print()

result = subprocess.run(
    ["swift", "run", "ShopPilotVerify1100"],
    cwd=".",
)

sys.exit(result.returncode)
