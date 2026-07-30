# Aspire V12 → ShopPilot Feature Parity Matrix

**Source:** Vectric Aspire V12 User Guide TOC + What’s New  
**Status keys:** `[ ]` not started · `[~]` in progress · `[x]` shipped · `[-]` deferred (date) · `[!]` blocked  

Track ownership in your PM tool; keep this file as the living checklist.

---

## A. Platform & job

| ID | Aspire capability | Stage | Pri | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| A01 | New job / open / save | All | P0 | [ ] | `.shoppilot` package |
| A02 | Job setup single-sided | Setup | P0 | [ ] | |
| A03 | Job setup double-sided | Setup | P1 | [ ] | |
| A04 | Job setup rotary | Setup | P1 | [ ] | Z origin center/surface |
| A05 | Edit sheet forms | Setup | P1 | [ ] | |
| A06 | Multi-sheet management | Setup | P1 | [ ] | |
| A07 | Job templates | Setup | P1 | [ ] | |
| A08 | Document variables | Setup | P2 | [ ] | |
| A09 | Calculation edit boxes | All | P0 | [ ] | |
| A10 | Options / preferences | All | P0 | [ ] | |
| A11 | Machine online/manual config | Setup | P0 | [ ] | |
| A12 | Kickstarter / onboarding | Setup | P0 | [ ] | |
| A13 | Crash recovery | All | P1 | [ ] | |
| A14 | Units mm/inch independence vs post | Setup | P0 | [ ] | Aspire principle |

## B. Views & chrome

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| B01 | 2D canvas | P0 | [ ] |
| B02 | 3D canvas | P0 | [ ] |
| B03 | Split 2D+3D | P1 | [ ] |
| B04 | Stage rail layouts | P0 | [ ] |
| B05 | Visibility chips (vec/bmp/tp/components/keepouts) | P0 | [ ] |
| B06 | View cube / presets | P0 | [ ] |
| B07 | Orthographic mode | P1 | [ ] |
| B08 | Draw in 3D view | P1 | [ ] |
| B09 | Vectors in 3D overlay | P1 | [ ] |
| B10 | Multi-sided view | P1 | [ ] |
| B11 | Layer/sheet/level quick controls | P0–P1 | [ ] |
| B12 | Command palette ⌘K | P0 | [ ] |
| B13 | Context coach / help | P0 | [ ] |
| B14 | Customizable shortcuts | P1 | [ ] |
| B15 | Unified import | P0 | [ ] |

## C. 2D create

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| C01 | Polyline | P0 | [ ] |
| C02 | Arc | P0 | [ ] |
| C03 | Circle | P0 | [ ] |
| C04 | Ellipse | P0 | [ ] |
| C05 | Rectangle | P0 | [ ] |
| C06 | Polygon | P1 | [ ] |
| C07 | Star | P1 | [ ] |
| C08 | Freehand | P1 | [ ] |
| C09 | Text | P0 | [ ] |
| C10 | Text on curve | P1 | [ ] |
| C11 | Text to curves | P0 | [ ] |
| C12 | Engraving fonts | P1 | [ ] |
| C13 | Dimensions | P1 | [ ] |
| C14 | Fillet | P0 | [ ] |
| C15 | Extend | P1 | [ ] |
| C16 | Offset | P0 | [ ] |
| C17 | Vector boundary | P1 | [ ] |
| C18 | Vector texture | P2 | [ ] |
| C19 | Plate production | P2 | [ ] |

## D. 2D edit & structure

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| D01 | Select / multi-select | P0 | [ ] |
| D02 | Node edit | P0 | [ ] |
| D03 | Transform handles | P0 | [ ] |
| D04 | Move / size / rotate / mirror | P0 | [ ] |
| D05 | Align | P0 | [ ] |
| D06 | Group/ungroup | P0 | [ ] |
| D07 | Array copy | P0 | [ ] |
| D08 | Circular copy | P1 | [ ] |
| D09 | Copy along vectors | P1 | [ ] |
| D10 | Join (straight/smooth/endpoints) | P0 | [ ] |
| D11 | Boolean weld/overlap/subtract | P0 | [ ] |
| D12 | Trim interactive | P0 | [ ] |
| D13 | Fit curves | P1 | [ ] |
| D14 | Distort | P2 | [ ] |
| D15 | Nest parts | P1 | [ ] |
| D16 | Vector validator | P1 | [ ] |
| D17 | Vector unwrapper | P1 | [ ] |
| D18 | Measure/inspect | P0 | [ ] |
| D19 | Layers | P0 | [ ] |
| D20 | Import DXF/DWG/EPS/AI/PDF/SVG | P0 | [ ] |
| D21 | SKP import | P2 | [ ] |
| D22 | Trace bitmap | P0 | [ ] |
| D23 | Edit/crop bitmap | P1 | [ ] |
| D24 | PDF export | P1 | [ ] |

## E. 3D model

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| E01 | Components + levels tree | P0 | [ ] |
| E02 | Combine Add | P0 | [ ] |
| E03 | Combine Subtract | P0 | [ ] |
| E04 | Combine Merge high | P0 | [ ] |
| E05 | Combine Low | P0 | [ ] |
| E06 | Combine Multiply | P2 | [ ] |
| E07 | Dynamic height/tilt/fade | P0 | [ ] |
| E08 | Level mirror modes (8) | P1 | [ ] |
| E09 | Level clipping | P2 | [ ] |
| E10 | Shape angled | P0 | [ ] |
| E11 | Shape round | P0 | [ ] |
| E12 | Shape smooth | P0 | [ ] |
| E13 | Shape flat plane | P0 | [ ] |
| E14 | Shape custom | P1 | [ ] |
| E15 | Two-rail sweep | P1 | [ ] |
| E16 | Extrude and weave | P1 | [ ] |
| E17 | Turn and spin | P1 | [ ] |
| E18 | Emboss | P1 | [ ] |
| E19 | Sculpting | P1 | [ ] |
| E20 | Smooth components | P1 | [ ] |
| E21 | Scale height | P0 | [ ] |
| E22 | Offset model | P1 | [ ] |
| E23 | Add draft | P2 | [ ] |
| E24 | Replace below | P2 | [ ] |
| E25 | Zero plane | P0 | [ ] |
| E26 | Texture area | P1 | [ ] |
| E27 | Component from bitmap | P0 | [ ] |
| E28 | Component from visible | P1 | [ ] |
| E29 | Bake components | P1 | [ ] |
| E30 | Clear/split | P1 | [ ] |
| E31 | Import 3D flat/double | P0 | [ ] |
| E32 | Import 3D rotary | P1 | [ ] |
| E33 | Position model | P0 | [ ] |
| E34 | 3D segment | P2 | [ ] |
| E35 | Slice model | P2 | [ ] |
| E36 | Cross-section vector | P1 | [ ] |
| E37 | Boundary from components | P1 | [ ] |
| E38 | Export STL | P0 | [ ] |
| E39 | Clipart / library | P1 | [ ] |

## F. Toolpaths

| ID | Strategy / feature | Pri | Status |
| --- | --- | --- | --- |
| F01 | Material setup flat | P0 | [ ] |
| F02 | Material setup rotary | P1 | [ ] |
| F03 | Profile 2D | P0 | [ ] | **Key fields:** Vector selection (single/multiple), operation type (cut/outline/inner-outer), depth/z-layers, tool selection from DB, feed rate & spindle speed, step-down, tabs (size/count/placement), keep-out zones, lead-in/out arcs (length/type), calculation edit boxes for offset, rapid clearance. Form refs: 2D Profile Toolpath.
| F04 | Pocket | P0 | [ ] | **Key fields:** Vector selection (closed boundaries), operation type (clear/finish/partial), pocketing strategy (zigzag/zigzag-angled/spiral/offset), depth/z-layers with step-down, tool selection, feed/speed, tabs, keep-out zones (islands), lead-in/out, stock allowance (left on final pass), peck mode for deep pockets. Form refs: Pocketing Toolpath.
| F05 | Drill | P0 | [ ] | **Key fields:** Vector selection (points/circles), tool selection (drill/end mill), depth/z, feed rate, spindle speed, peck cycle parameters (depth/retract), dwell time at bottom, rapid clearance, array copy for pattern drilling. Form refs: Drilling Toolpaths.
| F06 | V-Carve | P0 | [ ] | **Key fields:** Vector selection with depth-per-vector coloring, tool selection (V-bit angle: 30/45/90°), feed/speed, step-over (based on tip width at deepest cut), operation type (standard/relief), material setup, lead-in/out. Key differentiator: vectors carry Z-depth data that maps to shade/color in the vector layer. Form refs: V-Carve Toolpath.
| F07 | Quick engrave | P1 | [ ] | **Key fields:** Vector selection, tool selection (V-bit or small end mill), feed/speed, depth, simple single-pass operation. Less configurable than V-Carve — designed for speed over precision. Form refs: Quick Engraving Toolpath.
| F08 | Fluting | P1 | [ ] |
| F09 | Texture TP | P1 | [ ] |
| F10 | Prism | P1 | [ ] |
| F11 | Chamfer | P1 | [ ] |
| F12 | Moulding | P1 | [ ] |
| F13 | Photo V-Carve | P1 | [ ] | **Key fields:** Bitmap import, threshold/contrast settings, tool selection (V-bit), feed/speed, step-over, operation mode (standard/photo), material setup. Converts grayscale bitmap to depth-mapped vectors automatically. Form refs: Photo V-Carve Toolpath.
| F14 | Sketch carving | P1 | [ ] |
| F15 | Inlay pocket/plug | P1 | [ ] |
| F16 | VCarve inlay | P1 | [ ] |
| F17 | Thread milling | P2 | [ ] |
| F18 | 3D rough | P0 | [ ] | **Key fields:** Mesh selection (STL/OBJ), tool selection (ball nose/flat end mill diameter), strategy (adaptive/clearing/parallel/z-level), depth range (top/bottom of stock), step-over (% of tool dia), feed/speed, rapid clearance, rest-roughing option. Form refs: 3D Rough Toolpath.
| F19 | 3D finish | P0 | [ ] | **Key fields:** Mesh selection, tool selection (ball nose diameter), strategy (parallel/offset-perimeter/multi-axis/scallop-height), scallop height target, step-over calculated from scallop + tool dia, feed/speed, rapid clearance, direction (bidirectional/unidirectional), lead-in/out. Form refs: 3D Finish Toolpath.
| F20 | Array copy TP | P1 | [ ] |
| F21 | Merged TP | P1 | [ ] |
| F22 | Templates | P1 | [ ] |
| F23 | Tiling manager | P2 | [ ] |
| F24 | Tabs | P0 | [ ] |
| F25 | Keep-out zones | P0 | [ ] |
| F26 | Toolpath tree | P0 | [ ] |
| F27 | Edit/dup/delete/recalc | P0 | [ ] |
| F28 | Preview simulation | P0 | [ ] |
| F29 | Time estimate | P0 | [ ] |
| F30 | Dirty flag / no silent auto-recalc | P0 | [ ] |
| F31 | Laser cut/fill | P1 | [ ] |
| F32 | Laser picture | P1 | [ ] |
| F33 | Vector selector | P0 | [ ] |

## G. Tools, posts, shop

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| G01 | Tool database | P0 | [ ] |
| G02 | Material library | P0 | [ ] |
| G03 | Machine profiles | P0 | [ ] |
| G04 | Post library | P0 | [ ] |
| G05 | Save toolpaths | P0 | [ ] |
| G06 | Job sheet | P1 | [ ] |
| G07 | Naming variables | P2 | [ ] |
| G08 | Remote tool DB | P3 | [ ] |
| G09 | Post Studio editor | P2 | [ ] |
| G10 | Post change log | P2 | [ ] |

## H. Gadgets / recipes

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| H01 | Rounding TP | P1 | [ ] |
| H02 | Keyhole | P1 | [ ] |
| H03 | Drag knife | P2 | [ ] |
| H04 | Wrapped fluting layout | P1 | [ ] |
| H05 | Wrapped spiral layout | P1 | [ ] |
| H06 | Celtic weave | P2 | [ ] |
| H07 | Setup sheet editor | P1 | [ ] |
| H08 | Job recipes (new) | P0 | [ ] |

## I. Rotary advanced

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| I01 | Rotary job basics | P1 | [ ] |
| I02 | Wrap 2D toolpaths | P1 | [ ] |
| I03 | Spiral toolpaths | P1 | [ ] |
| I04 | Rotary 3D modelling | P2 | [ ] |
| I05 | Twisted/spiral model features | P2 | [ ] |
| I06 | Import models rotary | P2 | [ ] |

## J. Machine (beyond Aspire)

| ID | Capability | Pri | Status |
| --- | --- | --- | --- |
| J01 | Connect serial/sim | P0 | [ ] |
| J02 | Jog / home / zero | P0 | [ ] |
| J03 | Stream G-code | P0 | [ ] |
| J04 | Hold / resume / reset | P0 | [ ] |
| J05 | Console TX/RX | P0 | [ ] |
| J06 | Pre-flight checklist | P0 | [ ] |
| J07 | Live keep-out awareness | P1 | [ ] |

## K. File types

| ID | Format | Direction | Pri | Status |
| --- | --- | --- | --- | --- |
| K01 | Native project | RW | P0 | [ ] |
| K02 | DXF/DWG | In | P0 | [ ] |
| K03 | EPS/AI/PDF/SVG | In | P0 | [ ] |
| K04 | SKP | In | P2 | [ ] |
| K05 | BMP/JPG/PNG/TIF | In | P0 | [ ] |
| K06 | STL/OBJ/3MF | In/Out | P0 | [ ] |
| K07 | G-code | Out | P0 | [ ] |
| K08 | CRV/CRV3D | In research | P3 | [ ] | Clean-room only if pursued |

---

## Coverage summary

| Area | Count (approx) | P0 subset |
| --- | --- | --- |
| Full matrix rows | ~150+ | ~45–55 for first shippable “serious” Mac CAM+control |
| Aspire strategies | 25+ | Profile, pocket, drill, V-carve, 3D rough/finish, preview |
| Machine (ours) | 7 | All P0 for Control path |

Update **Status** column as epics complete. PM owns weekly parity review.

---

## L. Profile Toolpath — Form Fields (SPK-0002)

Source: [Vectric Aspire V12 2D Profile Toolpath docs](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/uiProfileMachineForm/index.html)

| ID | Field | Type | Default | Description |
| --- | --- | --- | --- | --- |
| L01 | Cut Depth (C) | float | 0.125 in | Depth of the toolpath relative to Start Depth |
| L02 | Start Depth (D) | float | 0.0 | Base depth; 0 for surface cuts, deeper for pocket-bottom profiling |
| L03 | Pass Depths | list | [auto] | Per-pass Z depths; auto-calculated from tool Pass Depth with ±15% optimization |
| L04 | Maintain Exact Step Depth | bool | false | Disables step-size variation for precise laminated cuts |
| L05 | Set Last Pass Thickness | float | N/A | Specify last pass as remaining material thickness instead of absolute depth |
| L06 | Number of Passes | int | [auto] | Force specific number of evenly-spaced passes (overrides tool Pass Depth) |
| L07 | Cut Type | enum | Outside | Position relative to vector: **Outside** / **Inside** / **On** |
| L08 | Cutting Direction | enum | Climb | **Conventional** or **Climb** machining direction |
| L09 | Allowance Offset | float | 0.0 | Overcut (negative) or undercut (positive) offset from selected shape |
| L10 | Last Pass Allowance | float | 0.0 | Separate allowance for final pass only; cuts to exact size on last pass |
| L11 | Reverse Last Pass Direction | bool | false | Reverses cutting direction of the last pass to minimize witness marks |
| L12 | Use Vector Start Point | bool | true | Force plunge and start at vector's first node point (green box) |
| L13 | Add Tabs | bool | false | Enable tab/bridge creation to hold parts in material during cutting |
| L14 | Tab Length | float | 0.125 in | Length of each tab along the cut edge |
| L15 | Tab Thickness | float | 0.031 in | Thickness measured from bottom of Cut Depth (not material bottom) |
| L16 | Create 3D Tabs | bool | false | Triangular-section tabs; cutter ramps up/down without Z lift stops |
| L17 | Ramp Type | enum | Smooth | Plunge strategy: **Smooth** / **ZigZag** / **Spiral** (no lead-in) |
| L18 | Ramp Distance | float | 0.125 in | Horizontal distance for ramp moves into material |
| L19 | Ramp Angle | float | N/A | Entry angle for cutters that cannot plunge vertically |
| L20 | Lead-In Type | enum | None | **None** / **Straight Line** / **Circular Arc** lead-in move |
| L21 | Lead-In Length | float | 0.0625 in | Length of the lead-in move |
| L22 | Lead-In Angle | float | 45° | Angle at which straight-line lead approaches the edge |
| L23 | Circular Lead Radius | float | N/A | Radius for arc-style lead-in (auto-calculated from angle) |
| L24 | Do Lead Out | bool | false | Add an exit lead move at end of toolpath |
| L25 | Overcut Distance | float | 0.015 in | Cutter machines past start point for edge quality |
| L26 | Order Strategy | enum | Optimize | Vector cutting order: **Selection Order** / **Left-to-Right** / **Bottom-to-Top** / **Grid** |
| L27 | Start At Mode | enum | Optimize | Start-point strategy: **Keep Current** / **Optimize** / **Closest on Bounding Box** |
| L28 | Sharp External Corner | bool | false | Mimic vector angle at external corners for sharp V-bit cuts |
| L29 | Sharp Internal Corner (3D) | bool | false | Angled tip movement into internal corners for sharp V-bit results |
| L30 | Safe Z | float | 0.25 in | Height above job for rapid / max feed-rate travel |
| L31 | Home Position | (x,y) | (0,0) | Position tool travels to before/after machining |
| L32 | Project onto 3D Model | bool | false | Drop toolpath down in Z onto a defined 3D model surface |
| L33 | Vector Selection | multi-select | all | Select vectors by properties or position; supports TP templates |
| L34 | Name | string | [auto] | Custom name for the toolpath entry

---

## M. Pocket Toolpath — Form Fields (SPK-0002)

Source: [Vectric Aspire V12 Pocketing Toolpath docs](https://docs.vectric.com/docs/V12.0/VCarvePro/ENU/Help/form/uiPocketMachineForm/index.html)

| ID | Field | Type | Default | Description |
| --- | --- | --- | --- | --- |
| M01 | Cut Depth (C) | float | 0.125 in | Depth of pocket relative to Start Depth |
| M02 | Start Depth (D) | float | 0.0 | Base depth; 0 for surface pockets, deeper for stepped regions |
| M03 | Pass Depths | list | [auto] | Per-pass Z depths; auto from tool Pass Depth with ±15% optimization |
| M04 | Maintain Exact Step Depth | bool | false | Disables step-size variation for precise laminated cuts |
| M05 | Set Last Pass Thickness | float | N/A | Specify last pass as remaining material thickness |
| M06 | Number of Passes | int | [auto] | Force specific number of evenly-spaced passes |
| M07 | Tool Selection | list | [1 tool] | Single or multiple tools; each removes max from unmachined areas, always leaves allowance for final tool |
| M08 | Strategy | enum | Offset | Fill pattern: **Offset** (concentric) / **Raster** (straight-line) |
| M09 | Cut Direction | enum | Climb | For Offset strategy: **Climb (CCW)** or **Conventional (CW)** |
| M10 | Raster Angle | float | 0° | Angle of raster passes; 0°=X-axis parallel, 90°=Y-axis parallel |
| M11 | Profile Pass | enum | Last | Edge cleanup timing: **First** / **Last** / **No Profile Pass** |
| M12 | Pocket Allowance | float | 0.0 | Material left on pocket walls for profile pass to clean up (prevents edge marking) |
| M13 | Ramp Plunge Moves | bool | false | Use ramping instead of vertical plunge into pocket |
| M14 | Use Vector Selection Order | bool | false | Machine pockets in selection order vs. optimized shortest path |
| M15 | Safe Z | float | 0.25 in | Height above job for rapid travel |
| M16 | Home Position | (x,y) | (0,0) | Position tool travels to before/after machining |
| M17 | Project onto 3D Model | bool | false | Drop pocket toolpath onto a defined 3D model surface |
| M18 | Vector Selection | multi-select | all | Select closed boundary vectors; supports TP templates |
| M19 | Name | string | [auto] | Custom name for the toolpath entry

---

## N. Drill Toolpath — Form Fields (SPK-0002)

Source: [Vectric Aspire V12 Drilling Toolpaths docs](https://docs.vectric.com/docs/V12.5/Aspire/ENU/Help/form/Drilling%20Toolpath/index.html)

| ID | Field | Type | Default | Description |
| --- | --- | --- | --- | --- |
| N01 | Cut Depth (C) | float | 0.25 in | Depth of drilled hole relative to Start Depth |
| N02 | Start Depth (D) | float | 0.0 | Base depth; 0 for surface drilling, deeper for pocket-bottom holes |
| N03 | Tool Selection | single | [1 drill] | Single drill/end mill selected from Tool Database |
| N04 | Peck Drilling | bool | false | Enable peck cycle: drill Pass Depth → retract → repeat until full depth |
| N05 | Retract Mode | enum | Above Previous | **Above Cutting Start** (fixed R above start) / **Above Previous Pass Height** (relative R) |
| N06 | Retract Gap (R) | float | 0.0625 in | Distance for peck retract; fixed or relative depending on Retract Mode |
| N07 | Dwell at Bottom | bool | false | Pause drill at hole bottom before retracting each pass |
| N08 | Dwell Time | float | 0.0 | Duration of dwell pause at bottom of each peck pass (seconds) — requires PP support |
| N09 | Use Vector Selection Order | bool | false | Machine drill points in selection order vs. optimized shortest path |
| N10 | Safe Z | float | 0.25 in | Height above job for rapid travel |
| N11 | Home Position | (x,y) | (0,0) | Position tool travels to before/after machining |
| N12 | Project onto 3D Model | bool | false | Drop drill points onto a defined 3D model surface |
| N13 | Vector Selection | multi-select | all | Select closed vectors (centers drilled) or point vectors; supports TP templates |
| N14 | Name | string | [auto] | Custom name for the toolpath entry

---

## O. V-Carve Toolpath — Form Fields (SPK-0002)

Source: [Vectric Aspire V12 V-Carve Toolpath docs](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/VCarve%20Toolpath%20Creator/index.html)

| ID | Field | Type | Default | Description |
| --- | --- | --- | --- | --- |
| O01 | Cut Depth (C) | float | 0.125 in | Depth of V-carving relative to Start Depth; per-vector Z-depth drives shade/color mapping |
| O02 | Start Depth (D) | float | 0.0 | Base depth; 0 for surface carving, deeper for pocket-bottom engraving |
| O03 | Flat Depth Mode | bool | false | Enable flat-bottomed carving mode with a specified depth limit |
| O04 | Flat Depth Value (F) | float | N/A | Maximum depth for flat-bottomed V-carving; when off, toolcarves to full vector-defined depth |
| O05 | Tool Selection | single | [1 V-bit] | V-bit or ball nose tool from Tool Database; angle drives path calculation |
| O06 | V-Bit Angle | float | 90° | Angle of the V-bit cutter; common presets: **30°** / **45°** / **90°** |
| O07 | Use Clearance Tools | bool | false | Enable multi-tool roughing with end mills/ball nose before V-carving pass |
| O08 | Clearance Tool List | list | [empty] | List of clearance tools; each removes max unmachined area, leaves allowance for V-bit |
| O09 | Clearance Strategy | enum | Offset | First clearance tool fill: **Offset** / **Raster** |
| O10 | Clearance Cut Direction | enum | Climb | For first clearance tool: **Climb (CCW)** or **Conventional (CW)** |
| O11 | Clearance Raster Angle | float | 0° | Angle of raster passes for clearance tool |
| O12 | Ramp Plunge Moves | bool | false | Apply ramping to clearance tool plunge moves |
| O13 | Corner Sharpen | bool | false | Raise engraving tool tip into narrower regions; available for 2nd+ tools only |
| O14 | Use Vector Start Points | bool | true | Align profile/offset start points to boundary vector start points |
| O15 | Use Vector Selection Order | bool | false | Machine vectors in selection order vs. optimized shortest path |
| O16 | Safe Z | float | 0.125 in | Height above job for rapid travel (typically lower than Profile) |
| O17 | Home Position | (x,y) | (0,0) | Position tool travels to before/after machining |
| O18 | Project onto 3D Model | bool | false | Drop V-carve toolpath onto a defined 3D model surface |
| O19 | Vector Selection | multi-select | all | Select vectors with per-vector Z-depth data; supports TP templates |
| O20 | Name | string | [auto] | Custom name for the toolpath entry

---

## Field Mapping Summary (SPK-0002)

### Cross-strategy common fields

All four strategies share these positional/selection fields:

| Common Field | Profile | Pocket | Drill | V-Carve |
| --- | --- | --- | --- | --- |
| Start Depth (D) | ✓ | ✓ | ✓ | ✓ |
| Cut Depth (C) | ✓ | ✓ | ✓ | ✓ |
| Safe Z | ✓ | ✓ | ✓ | ✓ |
| Home Position | ✓ | ✓ | ✓ | ✓ |
| Project onto 3D Model | ✓ | ✓ | ✓ | ✓ |
| Vector Selection | ✓ | ✓ | ✓ | ✓ |
| Name | ✓ | ✓ | ✓ | ✓ |

### Strategy-specific field counts

| Strategy | Unique Fields | Total Fields (incl. common) |
| --- | --- | --- |
| Profile | 34 | 34 |
| Pocket | 19 | 19 |
| Drill | 14 | 14 |
| V-Carve | 20 | 20 |

### Key differentiators per strategy

- **Profile**: Tab system (length/thickness/3D), lead-in/out arcs, corner sharpening, order strategies (L→R/B→T/Grid)
- **Pocket**: Multi-tool clearance chain, Offset vs Raster fill patterns, pocket allowance for edge cleanup
- **Drill**: Peck cycle with retract modes (fixed vs relative), dwell time at hole bottom
- **V-Carve**: Per-vector Z-depth shading, V-bit angle parameterization, flat-bottom mode, multi-tool clearance with corner sharpen

### CSV output

A summary CSV is available at `docs/planning/form_fields_mapping.csv` with columns: Strategy, Field Name, Type, Default, Description — covering all 87 fields across the four strategies.
