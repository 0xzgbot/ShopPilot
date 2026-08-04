# Extraction: izFO02etvTg (enriched)

## capabilities_mentioned
- Chamfer toolpath (V-bit / ball-nose / engraving tool)
- Chamfer width ↔ cut depth coupling (derived from tool angle)
- Overcut parameter (flat-tip V-bit compensation)
- Max cut depth readout (V-bit = cut depth; ball-nose > cut depth)
- Chamfer direction: inside/outside + slope up/down (arrow tip = deepest point)
- Countersunk hole workflow (offset pocket by chamfer width)
- Profile cutout after chamfer (same vector)
- Material setup pre-check (thickness, datum, Z0 surface, rapid gaps)
- `z=` thickness shortcut

## workflow_steps
1. Open file → toolpath tab → CHECK material setup (thickness 0.5, datum bottom-left, Z0 on material surface — critical for chamfer, machining down from surface).
2. Select vector(s) → chamfer toolpath.
3. Tool: V-bit from tool DB (60° 1/4" example) — feeds/speeds per machine; angle field grayed out for V-bit (pulled from tool); editable only for ball-nose.
4. Set chamfer width OR cut depth — fields auto-calculate each other from tool angle (e.g. 0.25 width ⇒ cut depth; or `z=` for full depth).
5. Optional overcut for flat-tip V-bits (0.1 or 0.01) — compensates flat spot so edge of flat runs the line; watch max cut depth.
6. Choose inside/outside + slope up/down (arrow tip = deepest point).
7. Calculate (may warn "cut through material" — expected), preview selected toolpath.
8. For countersink: copy chamfer width → offset vector inward by that width → pocket toolpath full depth on offset vector.

## parameters_concepts
- chamfer width vs cut depth (angle-derived, coupled)
- overcut (flat-tip compensation)
- max cut depth (read-only; ball-nose cuts deeper than specified to hit width)
- inside/outside, slope up/down
- 60° V-bit → 30° chamfer angle per side

## gotchas_warnings
- V-bit angle is locked in chamfer form (comes from tool DB) — ball-nose is where you set angle
- Flat-tip V-bit without overcut leaves a step at the line
- Chamfer cuts through material → warning (expected)
- Test parts needed to tune overcut distance
- Profile cutout on the SAME vector after chamfer cuts the part out (that's the point — separate part)

## lean_relevance
**should**

## notes
Chamfer is the "beveled edge" companion to V-Carve; the width↔depth coupling is the key parameter concept (derived from tool angle, like V-Carve's emergent depth). The countersink workflow (offset by chamfer width → pocket) is a reusable pattern. Not P0 but cheap to implement after V-Carve since it shares the angle-geometry math.
