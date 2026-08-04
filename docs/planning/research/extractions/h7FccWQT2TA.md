# Extraction: h7FccWQT2TA (enriched)

## capabilities_mentioned
- V-Carve toolpath
- V-bit selection (60°/90°)
- start depth
- flat depth
- no cut-depth field (depth derived from tool angle + vector width)
- tool database feeds/speeds
- toolpath rename
- 3D preview of visible toolpath
- closed-vector requirement
- recalculate on parameter change

## workflow_steps
1. Check material setup first (thickness, datum, Z-zero on surface) -> open V-Carve toolpath -> set start depth (0 = top of material) -> optionally set flat depth to cap max depth -> pick V-bit from tool database (material+machine filtered) -> optionally add clearance tool -> rename toolpath -> calculate -> preview visible toolpath in 3D

## parameters_concepts
- start depth
- flat depth
- tool angle (60 vs 90 deg)
- material thickness
- rapid Z gap
- home/start position
- feeds/speeds from tool DB

## gotchas_warnings
- V-Carve depth is set by tool angle + vector width — no manual cut depth
- V-carving requires CLOSED vectors
- narrow letter pairs (r/i) can collide when start depth raised
- zero off the actual surface you carve into
- material must be flat; machine must be level
- wide vector gaps can push the V-bit through the material — use flat depth to cap
- recalculate after changing any parameter
- scripty fonts behave differently than spaced letters

## lean_relevance
**must**

## notes
The single most important V-Carve reference. Depth is emergent (angle+width), not entered; flat depth is the safety cap; closed vectors are mandatory. Start depth is the 'bolder lettering' trick. Tool DB drives feeds/speeds per material+machine.
