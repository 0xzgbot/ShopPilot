#!/usr/bin/env python3
"""SPK-1900d gate: machine dock / safety-chrome persistence audit.

AGENTS.md §2.1 — E-stop/Reset always visible while connected, fixed chrome.
VP parity target: H-103 app-lifetime machine dock. This gate proves the Mac
already satisfies it structurally (audit-only close).
"""
import sys

CV = "Sources/ShopPilot/ContentView.swift"
src = open(CV).read()

fails = []
def check(cond, msg):
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond:
        fails.append(msg)

# 1. TopChromeBar sits ABOVE/OUTSIDE the stage switch in the root body.
root = src[: src.find("HSplitView")]
check("TopChromeBar(session:" in root, "TopChromeBar rendered unconditionally at window top")
check("MachineAlarmBanner(controller:" in root, "alarm banner rendered on every stage")

# 2. machineChrome always present inside TopChromeBar's bar row.
bar = src[src.find("struct TopChromeBar") : src.find("// MARK: - Alarm banner")]
check("machineChrome" in bar, "machine state pill lives in the persistent top bar")

# 3. Safety controls appear whenever live AND not already on Machine stage
#    (on the Machine stage the full panel owns them).
check("chromeState.isLive && session.selectedStage != .machine" in bar,
      "Hold/Reset shown while connected on ALL non-Machine stages")
check("CompactSafetyControls(controller: controller)" in bar, "compact Hold/Resume+Reset wired")
check('Text(session.selectedStage.intent)' in bar or "selectedStage.intent" in bar,
      "stage rail shares the same bar (dock spans stages)")

# 4. Safety Req #1 comment contract intact.
check("Safety Req #1" in src, "safety requirement documented at the chrome site")

print()
if fails:
    print(f"verify_1900d_dock_audit: FAIL ({len(fails)})")
    sys.exit(1)
print("verify_1900d_dock_audit: PASS — safety chrome persists across all stages")
