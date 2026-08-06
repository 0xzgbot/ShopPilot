# Reference Installer Breakdown (V12.5.1.0) & "Basic CNC App" Feature Set

**Date:** 2026-08-03
**Source:** reference trial installer (520MB NSIS, V12.5.1.0 Build 12738) unpacked to
`/tmp/installer_unpacked` (867MB, 1,368 files) + 4 parallel analysis passes.
**Purpose:** Ground ShopPilot's feature surface in the real product, then distill what a
**basic** Mac CNC app must have ("the features all CNC apps have").
**Compliance:** Feature/parameter NAMES only — no proprietary assets, formats, or content
copied. CRV reverse-engineering remains out of scope.

---

## 1. What the installer actually is

| Asset | Evidence |
|---|---|
| Product | Reference **Trial Edition 12.5** (V12.5.1.0 Build 12738, 2026-05-29) |
| Installer | NSIS-3 Unicode self-extractor; 1,368 files |
| App | trial-edition CAM suite (86MB) — **no machine-control UI** (control = posts + machine database) |
| Key binaries | OpenNURBS (3DM import), SketchUpAPI (SKP import), ZXing (QR), osgViewer (3D view), pstill (PDF), BugSplat (crash reports) |
| Data payloads | PostP/ (75 .pp), postp.ppdb (SQLite: 964 posts + machine configs), ToolpathDefaults/ (17), ToolDatabase/ (2 .vtdb), Gadgets/ (91), BitmapTextures/ (51), Templates/ (72 sheets), CabinetryImport/ (6 mappings) |

## 2. Feature surface (installer-verified)

### Job setup
- Single / **double-sided** / **rotary** job types; sheet + material + thickness; XY datum picker; Z-zero (surface/center); 72 stock sheet presets (6 imperial × 6 thickness, 6 metric × 6 thickness); oversized sheets → **Toolpath Tiling**; rotary = wrap model around cylinder (axis, orientation, auto-wrapping view, wrapped output).

### 2D design
- Draw: line/polyline, arc (4 construction modes), bezier, rectangle, circle, ellipse, polygon, star, freehand, text (+text-on-curve, text-in-box, text-to-curves).
- Edit: node edit (start/midpoint/bezier handles), trim, extend, join, fillet (normal/dog-bone/T-bone/plasma-drag), offset, mirror/rotate/move/size, align (incl. to curve/material/selection), boolean add/subtract/intersect/XOR, array/circular copy, dimensions (V12), **bitmap trace**, **vector texture (V12)**, layers (visibility/color/lock/DXF names).
- Import: crv3d, dxf, dwg, eps, ai, pdf, svg, stl, 3dm, skp, 3dClip, v3m, v3d, pvc + bitmaps. Export: DXF/SVG, STL, grayscale bitmap, PDF.

### 3D (Components model)
- Components + levels; combine modes: Add/Subtract/Merge/Merge-High/Merge-Low/Intersect/Normal/Add-Base; shape tools (round/smooth/angled/flat/custom/L-shape, cap/scale height); **sculpting brushes**; two-rail sweep / extrude; **Slice Model (V12)**; draft; 3D import STL/3DM/SKP; create component from visible model / **from toolpath preview**.

### Toolpaths (17 shipped strategies + variants)
Profile, Pocket (offset/raster, multi-tool, clearance pass), V-Carve (+engraving pass, flat depth, overcut), Drilling (+peck/dwell/**drill bank**), Chamfer, Fluting (V12.5), 3D Rough (z-level, rest machining, allowance), 3D Finish (raster/offset/spiral/zig-zag, final-pass stepover), Swept Profile/Moulding, Texture, Quick Engrave (diamond drag), Bevel Carving, Thread Milling (int/ext, RH/LH), Laser family (Cut / Cut&Fill / Fill / Picture / **Sketch Engraving**), Photo V-Carve, V-Carve Inlay (male/female/stepped, glue gap), Prism Carving, Plasma Profile.
- Shared subsystems: **tabs** (2D/3D, auto, constant distance), **ramping** (5 types incl. zig-zag, ramp ratio), **leads** (arc/line, angle), ordering/sorting/merge, boundaries + offsets, tolerances, cut direction (climb/conventional).
- Management: toolpath tree, groups, duplicate/delete/recalculate-all, merge toolpaths, **array copy toolpath**, **tiling**, **nesting**, templates (.ToolpathTemplate), preview simulation (2x–16x quality, playback), time/distance summary, **Keep-Out Zones (V12)**, component-from-preview, import toolpaths (PVC/V3M/V3D).

### Output
- **964 post-processors** in SQLite ppdb (75 shipped) — GRBL in/mm, **Grbl WrapY2A rotary**, Easel-Grbl, Shapeoko, BobsCNC, Carbide Motion ATC, Avid CNC (incl. wrap X2A/Y2A), X-Carve Pro, Openbuilds, LinuxCNC, Mach2/3/4, Centroid/Acorn, Masso, Duet, ShopBot (~28), industrial (Biesse/Homag/Kuka/Anderson…).
- `.pp` format: `POST_NAME`, `FILE_EXTENSION`, `UNITS`, `LINE_ENDING`, block numbering, `VAR X_POSITION = [X|C|X|1.3]` format-specifier grammar, tool-change/spindle capability flags, A-axis wrap.
- Job sheet = **HTML template** (`PrintSheetTemplate.html`, A4 CSS) rendered per toolpath.
- Machine database: OEM machine configs (make/model/series), cutting data per machine+material+tool, online tool-DB backup.

### V12.5 headline features (verified in binaries)
Keep-Out Zones · Sketch Carving · Laser Sketch Engraving · Fluting · V-Carve Inlay · Wrapping/auto-wrap · Double-sided (side flip, two-sided nest) · Cabinet import (KCD/Mozaik/Polyboard/SmartWOP/CabinetSense/CabinetPartsPro) · Gadget packages (.VectricGadget, signed).

### Trial limitations observed
Vector/model export disabled; laser module gated; content remote-fed (startup page, tutorials); no local "What's New" text on disk.

---

## 3. The "basic CNC app" feature set (what ALL CNC apps have)

Distilled from the above: the P0 core every hobby CNC app ships, in workflow order.
**This is the recommendation for ShopPilot's basic tier** (Core → Studio → Studio3D maps cleanly onto it).

| # | Area | Feature | Installer-verified reference | Effort |
|---|---|---|---|---|
| 1 | Job setup | New/open/save project; units (in/mm); sheet size + thickness + material; XY origin corner picker; Z-zero surface/center; **72 stock presets** (data, not code) | §2 Job setup | L |
| 2 | 2D draw | Line/polyline, arc, circle, ellipse, rectangle, polygon, text, offset, trim/extend, join, fillet, mirror/rotate/move/size, align, boolean weld/subtract, array copy, layers | §2 2D design | XL |
| 3 | Node edit | Start point, midpoint, bezier handles, nudge, make-start | `vcHandleEditTool`, Handle assets | M |
| 4 | Import | **DXF, SVG, EPS/PDF (vector)**, PNG/JPG/BMP (trace later), STL (3D later) | Import formats | L |
| 5 | Toolpaths P0 | **Profile** (on/outside/inside, depth+pass depth, climb/conventional, tabs, ramp, leads), **Pocket** (offset/raster + angle, allowance, islands), **V-Carve** (max depth, flat depth, engraving stepover), **Drill** (peck, dwell, retract) | ToolpathDefaults + form fields | XXL |
| 6 | Toolpath shared | Tool DB (13 classes), feeds/speeds, safe Z, tabs/ramps/leads blocks, ordering, time estimate, toolpath tree with recalc | §2 shared subsystems | XL |
| 7 | Post & output | **GRBL in/mm post** (ours: first-class), generic GCode, save toolpaths, **HTML job sheet** | ppdb Grbl posts; PrintSheetTemplate | M |
| 8 | Preview | 2D toolpath draw + 3D simulation (voxel/heightfield), playback, machined-area/material colors | Preview panel, BitmapTextures | XL |
| 9 | Machine control (ours, beyond the reference) | Serial connect (GRBL/FluidNC), DRO, jog/step, home, zero XYZ, stream with hold/resume/reset, console TX/RX, **e-stop always visible** | AGENTS.md §2 | XL |

**Deliberate exclusions for the basic tier** (Studio3D/advanced, per matrix): 3D components/sculpt, rotary, laser, photo V-carve, thread milling, tiling, nesting, cabinet import, gadgets, keep-out zones, drill banks, 964 posts.

### Why this set
- Every competitor in the class (Carbide Create, Estlcam, Fusion free, Easel) ships 1–9; the reference's P0 form fields (verified §2) match this exact surface.
- It's the *workflow-complete* floor: design → toolpath → post → run, with no dead ends.
- Existing ShopPilot Core already contains: serial transport, GRBL parser, streamer, G-code model, ToolDatabase, document model, geometry kernel — the gap is toolpath *calculation* (profile/pocket/v-carve/drill) + preview + the 72 presets + HTML job sheet.

---

## 4. Evidence index (for FEATURE_PARITY_MATRIX.md)

| Topic | Report |
|---|---|
| Toolpath strategy parameter surface (17 strategies, shared subsystems, Keep-Out Zones, node handles) | `/tmp/installer_reports/01_toolpaths.md` |
| Post-processor ecosystem (964 posts, .pp format, job sheet template, machine DB) | `/tmp/installer_reports/02_posts.md` |
| Data assets (tool DB taxonomy, 17 default tools, 72 sheets, 51 textures, 6 cabinet mappings) | `/tmp/installer_reports/03_assets.md` |
| UI/feature surface (job setup, 2D/3D, menus, gadgets, V12.5 headlines, trial limits) | `/tmp/installer_reports/04_ui_surface.md` |
| Raw string dumps (exe 15,831; ENU DLL 3,224) | `/tmp/exe_strings16.txt`, `/tmp/enu_strings16.txt` |
| Windows live-app capture (pending, user-run) | `docs/planning/WINDOWS_EXPLORER_PROMPT.md` |

## 5. Next steps
1. [ ] Merge evidence into FEATURE_PARITY_MATRIX.md (new section R, done in this commit).
2. [ ] Run the Windows explorer prompt on the trial PC → merge live form-field capture (Step 4/5 are the gaps).
3. [ ] Implement P0 toolpath calculators (Profile → Pocket → V-Carve → Drill) per matrix F03–F06 acceptance criteria.
4. [ ] Ship 72 stock presets + 17 default tool assignments + GRBL post + HTML job sheet as data assets.
