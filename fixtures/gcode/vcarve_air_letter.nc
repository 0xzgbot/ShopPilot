; ShopPilot fixture — V-CARVE air-cut (letter "V" path above stock), SIM ONLY
; Verify machine travel before real hardware. Spindle intentionally off.
G21 G90 G94
G0 Z5
G0 X10 Y30
G1 X25 Y10 F600
G1 X40 Y30
G1 X25 Y18
G1 X10 Y30
G0 Z10
M2
