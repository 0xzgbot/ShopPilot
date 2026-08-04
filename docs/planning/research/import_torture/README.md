# Import Torture Set — DXF/SVG fixtures for the vector validator

**Author:** ShopPilot research (original test files, no proprietary content) · **Date:** 2026-08-04
**Purpose:** deterministic inputs for the import path + validator preflight (PREFLIGHT_RULES R001–R004) and import-tolerance testing (SVG/DXF from Illustrator/Inkscape/Fusion/online clip sites). Hand-written ASCII DXF R12 + plain SVG — no CAD tool needed to regenerate.
**Location:** committed here (not under gitignored research/raw) so `ShopPilotTests` can reference them as fixtures.

## Files and expected findings

| File | Format | Defect class | Expected validator finding |
|---|---|---|---|
| `open_gap.dxf` | DXF | Polyline with 0.5 mm gap (3 pts, unclosed) | open vector |
| `open_tiny_gap.dxf` | DXF | Gap of 0.001 (tolerance edge case) | closed within 1e-3 tol; open at 1e-6 |
| `duplicate.dxf` | DXF | Two identical circles, same center/radius | overlapping contours / duplicate |
| `duplicate_offset.dxf` | DXF | Two circles offset by 0.01 | overlapping contours |
| `self_intersect.dxf` | DXF | Figure-8 polyline (6 pts crossing) | intersections |
| `zero_span.dxf` | DXF | Closed polyline with two identical consecutive vertices | zero-length span |
| `overlaps.dxf` | DXF | Two rectangles overlapping by 4 units | overlapping contours |
| `text_as_curves_open.dxf` | DXF | U-shaped open path (letter-like) | open vector (V-Carve mode ignores font intersections only) |
| `nested.dxf` | DXF | Circle inside circle (valid, intentional) | **clean — must NOT flag** |
| `fusion_units.dxf` | DXF | 25.4-unit square + `$INSUNITS=4` (mm) header | import-units handling (mm vs inch) |
| `inkscape_style.svg` | SVG | Groups + transforms, mm units, open path, duplicate rects | transform/group handling; open + dupe detection |
| `illustrator_arc.svg` | SVG | Cubic bezier closed blob, open bezier U, self-intersecting bezier | bezier conversion; open + self-intersect detection |

## Usage (unit tests)

Feed each file through the DXF/SVG importer + vector validator. Assert:
- open vectors detected where marked (R001)
- overlaps/intersections counted where marked (R002/R004)
- zero-length spans detected where marked (R003)
- nested/valid files pass clean (no false positives)
- unit metadata parsed ($INSUNITS / svg width attr) and applied to the job units

## Reproducible fixture verification

The defect classes above are enforced by a checked-in, stdlib-only verifier
(lesson from the 28/28 ad-hoc pass — keep it reproducible):

```bash
python3 scripts/verify_import_torture.py          # repo-relative default dir
python3 scripts/verify_import_torture.py --list   # list fixtures only
python3 scripts/verify_import_torture.py --dir <path>  # explicit dir
```

Exit code 0 = all checks pass (currently **28 checks**); 1 = any failure.
Run it after editing any fixture — a fixture that stops encoding its claimed
defect class will fail the suite.

## Notes / caveats

- Coordinates are in drawing units; `fusion_units.dxf` deliberately carries a `$INSUNITS=4` (mm) header so the importer can exercise unit conversion (25.4-unit square ⇒ 25.4 mm).
- The zero-span polyline uses `70 1` (closed) with a repeated vertex — some importers auto-merge; the validator should still report it or the importer must preserve it.
- SVG fixtures exercise group/transform flattening and bezier→polyline tolerance (arc tolerance concept from GRBL `$12`).
- For real-world corpus: grab a few public-domain SVGs from Inkscape examples later; these fixtures are the deterministic core.
