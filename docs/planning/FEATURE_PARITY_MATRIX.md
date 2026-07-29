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
