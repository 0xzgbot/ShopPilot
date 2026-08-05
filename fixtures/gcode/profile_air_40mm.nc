; ShopPilot fixture — PROFILE air-cut (40mm square), SIM ONLY
; Verify machine travel before real hardware. Spindle intentionally off.
G21 G90 G94
G0 Z5
G0 X0 Y0
G1 X40 Y0 F600
G1 X40 Y40
G1 X0 Y40
G1 X0 Y0
G0 Z10
M2
