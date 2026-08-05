; ShopPilot fixture — DRILL air-cut (4 holes, peck-style retracts), SIM ONLY
; Verify machine travel before real hardware. Spindle intentionally off.
G21 G90 G94
G0 Z5
G0 X10 Y10
G1 Z3 F300
G1 Z5 F600
G0 X20 Y10
G1 Z3 F300
G1 Z5 F600
G0 X10 Y20
G1 Z3 F300
G1 Z5 F600
G0 X20 Y20
G1 Z3 F300
G1 Z5 F600
G0 Z10
M2
