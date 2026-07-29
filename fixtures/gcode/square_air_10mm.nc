; ShopPilot fixture — SIM ONLY / verify machine travel before real hardware
; 10mm square at Z=5mm (air), mm mode
G21 G90 G94
G0 Z5
G0 X0 Y0
G1 X10 Y0 F300
G1 X10 Y10
G1 X0 Y10
G1 X0 Y0
G0 Z10
M2
