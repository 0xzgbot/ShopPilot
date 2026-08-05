# Happy-path import fixtures (SPK-SHAKEb)

Clean, valid inputs — the "must import cleanly" side of the import matrix.
The torture set lives in `docs/planning/research/import_torture/`; these are
its opposite: defect-free files every importer should accept without warnings.

| File | Format | Content | Expected |
| --- | --- | --- | --- |
| `happy_square.dxf` | ASCII DXF R12 | Closed LWPOLYLINE square (10–40), LINE, CIRCLE, `$INSUNITS=4` (mm) | 3 entities, all valid, no crossings |
| `happy_compose.svg` | SVG | rect + circle + closed triangle path + open bezier path, `width="100mm"` | 4 shapes, one closed one open |
| `happy_box.stl` | ASCII STL | 20×20×10 mm box, 12 facets / 36 vertices | rasterizes to a heightfield, no errors |

Gated by `python3 scripts/verify_import_torture.py` (happy-path section):
every file must parse and match its expected shape/defect-free profile.
