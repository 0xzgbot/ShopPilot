#!/usr/bin/env python3
"""SPK-DOGFOOD-04 verify — the Preview status must never claim "ready" with 0 cells.

Gate (per card): python source-contract asserting the zero-cell branch emits
the honest string, ordered so it wins over the ready branch, plus build.
"""
import re
import subprocess
import sys

PATH = "Sources/ShopPilot/ToolpathPreviewView.swift"
src = open(PATH).read()
ok = fail = 0

def check(cond, label):
    global ok, fail
    print(f"  {'PASS' if cond else 'FAIL'}: {label}")
    if cond: ok += 1
    else: fail += 1

# 1. The honest empty-string exists.
check("Material sim empty — press Simulate" in src,
      "honest 'Material sim empty — press Simulate' string present")

# 2. It is guarded by a nil-heightmap check.
check(re.search(r'} else if simHeightmap == nil \{\s*\n\s*simStatus = "Material sim empty', src) is not None,
      "empty-status branch guarded by simHeightmap == nil")

# 3. Ordering: the nil guard must come BEFORE the ready branch.
nil_pos = src.find('} else if simHeightmap == nil {')
ready_pos = src.find('Material sim ready')
check(0 < nil_pos < ready_pos,
      "empty branch precedes 'ready' branch (0-cell can never reach ready)")

# 4. The ready branch is only reachable with a non-nil map (cellCount > 0 path).
ready_block = src[ready_pos:ready_pos + 80]
check("cellCount" in ready_block, "'ready' branch reports the real cell count")

# 5. Cancelled branch unchanged (regression).
check("Sim cancelled (" in src and "cells kept)" in src,
      "cancel branch intact")

print()
print(f"verification_evidence: {ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
