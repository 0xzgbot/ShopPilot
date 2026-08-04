# Extraction: YNfSato4LvM (enriched)

## capabilities_mentioned
- material setup form (mandatory before toolpaths)
- active sheet indicator
- material thickness
- XY datum (lower-left etc, with offset option)
- Z0 position (material surface vs machine bed)
- rapid Z gap (clearance) + plunge gap
- home/start position XY + Z gap
- detailed summary graphic
- 3D model position in material (gap above/below, slider, dead-center/top/bottom double-click)
- model thickness must be < material thickness

## workflow_steps
1. Toolpath tab -> material setup -> verify thickness vs actual material -> set XY datum (matches machine zero) -> set Z0 (surface or bed) -> set rapid Z gap (safe traverse) + plunge gap (clear clamps) -> set home/start position -> keep detailed summary on -> for 3D: position model in material (gap above for thickness variance; top for negative shapes) -> OK -> create toolpaths

## parameters_concepts
- material thickness
- XY datum + offset
- Z0 (surface vs bed)
- rapid Z gap
- plunge gap
- home/start XY/Z
- model position (gap above/below)

## gotchas_warnings
- Software FORCES material setup before first toolpath — it's the contract with the machine
- Z0 must match what you actually set on the machine
- Rapid/plunge gaps must clear clamps and hold-downs
- 3D: keep a gap above model unless cutting negative shapes (dishes/recesses) — avoids flat spots from thickness variance
- Model thickness must be < material thickness

## lean_relevance
**must**

## notes
The mandatory preflight form. Confirms: material setup gates toolpath creation; Z-zero mode + datum + safe gaps are the machine contract. All must be reflected in ShopPilot's job setup.
