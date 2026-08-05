; ShopPilot fixture — CALIBRATION square air-cut (50mm, 2 passes), SIM ONLY
; Loaded by AppSession.loadFixtureGCodeIfNeeded when the session buffer is
; empty. Air-safe: all Z >= 0, spindle intentionally off. Verify machine
; travel before real hardware.
G21 G90 G94
G0 Z5
G0 X0 Y0
G1 X50 Y0 F300
G1 X50 Y50
G1 X0 Y50
G1 X0 Y0
G1 X50 Y0
G0 Z10
M2
