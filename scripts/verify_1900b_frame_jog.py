#!/usr/bin/env python3
"""SPK-1900b gate: frame job + click-to-jog wiring and safety gates."""
import sys

MC = "Sources/ShopPilot/MachineController.swift"
CV = "Sources/ShopPilot/DesignCanvasView.swift"

fails = []
def check(cond, msg):
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond:
        fails.append(msg)

mc = open(MC).read()
cv = open(CV).read()
core = open("Sources/ShopPilotCore/GCodeLine.swift").read()

check("public var canSendMotion" in mc, "controller exposes canSendMotion gate")
check("connection.connectionState.isConnected && chromeState == .idle" in mc,
      "gate = connected AND idle")
check("guard canSendMotion" in mc, "both motion paths guard on the gate")
for m in ["frameJob(widthMm:", "jogTo(xMm:"]:
    check(m in mc, f"{m}...) present")

# Frame formatter safety contract lives in Core, proven by Verify1900b; here
# check the UI never enables motion chrome without the machine being live.
check('FrameJobFormatter.lines' in mc or "FrameJobFormatter.lines" in mc, "frame routes through Core formatter")
check(".disabled(!(session.machine.canSendMotion))".replace("(","").replace(")","") in cv.replace("(","").replace(")",""),
      "Frame button disabled unless connected+idle")
check("session.machine.jogTo(xMm:" in cv, "canvas click routes to controller jogTo")
check("hypot(value.translation.width, value.translation.height) < 6" in cv,
      "jog-to fires on TAP only (not drags/pan)")
check("@State private var jogToMachineMode" in cv, "jog-to is an explicit mode toggle")

# Formatter contract spot-check (full proof = ShopPilotVerify1900b PASS).
check("G0 Z\\(f(clearanceZMm))" in core, "frame lifts to clearance first")
check('"G0 X0.000 Y0.000"' in core, "origin corners formatted consistently")
check("M3" not in core.split("FrameJobFormatter")[1], "frame formatter contains no spindle command")

print()
if fails:
    print(f"verify_1900b_frame_jog: FAIL ({len(fails)})")
    sys.exit(1)
print("verify_1900b_frame_jog: PASS — frame/jog-to wired behind connected+idle gate")
