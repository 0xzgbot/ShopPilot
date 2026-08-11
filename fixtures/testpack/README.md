# Test Pack — exercise every ShopPilot function

Generated test files for load → save → modify → export round-trips.
Everything here is **sim-safe**: no file points at real machine travel without
human verification.

| File | Format | What it exercises |
| --- | --- | --- |
| `MasterTest.shoppilot` | Native document | **The flagship.** 2 sheets (Front: 3 layers — Border / Artwork / Text; Back: 1 pocket layer), 5 toolpaths (real engine G-code): Border Profile, Back Pocket, Hole Pattern (8 drills), Text V-Carve, + **1 intentionally dirty placeholder** to test dirty-gating + Recalc All. Load → modify → save → export (G-code / job sheet / PDF). |
| `complex_artwork.svg` | SVG import | All importer primitives: rect (incl. rounded), circle ×2, ellipse, line ×2, polyline (open), polygon ×2, closed path, bezier path, quadratic path, **nested group with transform** → 15 shapes. Drag into Design or File → Import. |
| `complex_plate.dxf` | DXF R12 import | 4 layers (OUTLINE/POCKET/DECOR/DRILL), LWPOLYLINE pocket boundary (closed), 4 lines, 2 circles, 2 arcs, 5 small drill-point circles → 14 entities. Tests layer fidelity + entity variety. |
| `terrain_mesh.stl` | STL import (ASCII) | Procedural 2-hill terrain, **4,800 triangles** (60×40 grid) → Model stage relief (Rough 3D / Finish 3D / rest machining, relief text over it). 905 KB. |

## Suggested test flow

1. **Open `MasterTest.shoppilot`** (File → Open).
   - Verify 2 sheets in Setup; switch Front ↔ Back; the toolpaths follow the active sheet.
   - Cut stage: 5 toolpaths — Border Profile / Back Pocket / Hole Pattern / Text V-Carve / **Dirty Placeholder** (shows a dirty/needs-recalc dot).
   - Modify: drag a vector on the Front sheet → Border Profile goes dirty → Recalc All (watch the async spinner — no UI freeze).
   - Edit toolpath params (feed/depth/pass) and Recalc single.
   - Add an op via a **toolpath template**; save a new template.
   - Export: Save G-code (group-by-tool), **Job Sheet…** (A4 PDF), **design PDF export**.
   - Save As → reopen → everything persists (undo history too).
2. **Import `complex_artwork.svg`** in Design → vector ops (offset, boolean, fillet, dogbone, vector boundary, nest) → make toolpaths → export.
3. **Import `complex_plate.dxf`** → check layers arrive; pocket the LWPOLYLINE boundary; drill the 5 circles; export DXF back out.
4. **Import `terrain_mesh.stl`** → Model stage relief appears → Rough 3D + Finish 3D + Rest Machining toolpaths → Preview simulation on the sheet → job sheet.

## Regenerating

```bash
python3 scripts/gen_testpack.py                    # SVG / DXF / STL
./scripts/swift_locked.sh run ShopPilotTestPackGen # MasterTest.shoppilot (real codecs)
```

The verify gate (`./scripts/verify_locked.sh ShopPilotVerifyTestPack`) proves
all four files load through the real importers with usable content.
