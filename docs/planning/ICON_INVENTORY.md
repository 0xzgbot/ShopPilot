# ShopPilot — Mac-Native Icon Inventory

**Status:** List only — no artwork generated yet  
**Last updated:** 2026-08-01  
**Capability source:** [FEATURE_PARITY_MATRIX.md](./FEATURE_PARITY_MATRIX.md) (reference V12 User Guide TOC) + [UX_STAGE_SYSTEM.md](./UX_STAGE_SYSTEM.md)  
**Visual language:** Apple HIG + [SF Symbols](https://developer.apple.com/sf-symbols/) — **do not** clone third-party toolbar art  
**Density rule:** ≤12 primary toolbar icons per stage ([IconEnforcement.swift](../../Sources/ShopPilot/IconEnforcement.swift))

---

## Design rules

1. Prefer **SF Symbols** as-is; use **outline** weight in toolbars (Apple toolbar guidance).
2. Custom glyphs only when no clear SF Symbol exists; design as a **template SF Symbol** (monoline, black/clear, San Francisco optical size).
3. **Red accent = machine/safety only** (Hold, Reset, alarm).
4. App icon is separate from UI glyphs — SF Symbols must not appear in the app icon.
5. Progressive disclosure: primary ≤12 → overflow / ⌘K / recipes for the rest.
6. Palette / list rows still need glyphs even when the tool is not on the primary toolbar.

### Column key

| Column | Meaning |
| --- | --- |
| **Wave** | 1 = ship / primary chrome · 2 = Model + Design overflow · 3 = specialty / gadgets / laser / rotary |
| **SF candidate** | Preferred system symbol name |
| **Custom?** | `no` = use SF as-is · `maybe` = try SF first · `yes` = need custom SF-template glyph |
| **Live** | Currently used in source (path) · blank = planned |

---

## 0. Brand / system (not toolbar glyphs)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| APP-01 | App icon | Dock / Finder / About | 1 | — | yes | Icon Composer / Liquid Glass; no SF Symbols inside |
| APP-02 | Document icon `.shoppilot` | Finder | 1 | — | yes | macOS document icon set |
| APP-03 | File type badge G-code | Import / export lists | 1 | `doc.text` | no | Text badge OK for v1 |
| APP-04 | File type badge SVG | Import hub | 1 | `photo` | no | Live: `ImportHubView` |
| APP-05 | File type badge DXF | Import hub | 1 | `square.grid.2x2` | no | Live: `ImportHubView` |
| APP-06 | File type badge STL/OBJ/3MF | Import / Model | 2 | `cube` | no | |
| APP-07 | File type badge bitmap | Import | 1 | `photo` | no | BMP/JPG/PNG/TIF |

---

## 1. Stage rail

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| ST-01 | Setup | Stage rail | 1 | `gearshape` | no | Live: `StageEnum` |
| ST-02 | Design | Stage rail | 1 | `pencil.and.outline` | no | **Audit:** live uses `pen.toolpath` — verify availability; prefer `pencil.and.outline` or `scribble.variable` |
| ST-03 | Model | Stage rail | 1 | `cube.box` | no | Live: `StageEnum` |
| ST-04 | Cut | Stage rail | 1 | `scissors` | no | Live: `StageEnum` |
| ST-05 | Preview | Stage rail | 1 | `play.circle` | no | Live: `StageEnum`; coach uses `eye` — align |
| ST-06 | Machine | Stage rail | 1 | `cable.connector` | no | **Audit:** live uses `printer.tray` (misleading for CNC); coach uses `powerplug` — pick one Mac-native: prefer `cable.connector` or `memorychip` |
| ST-07 | Stage locked | Stage rail / Model empty | 1 | `lock.fill` | no | Live: `ContentView` |

### Stage symbol audit (ST-02 / ST-06)

Verified 2026-08-01 against system `name_availability.plist` (CoreGlyphs / CoreGlyphsPrivate):

| Symbol | Present? |
| --- | --- |
| `pen.toolpath` | **MISSING** — live `StageEnum` falls back to empty / broken glyph |
| `printer.tray` | **MISSING** — same |
| `pencil.and.outline`, `scribble.variable`, `cable.connector`, `cable.connector.slash`, `memorychip`, `cube.box`, `gearshape`, `scissors`, `play.circle`, `powerplug`, `pencil.and.ruler` | OK |

| Current (`StageEnum`) | Coach (`CoachPanelView`) | Recommended | Reason |
| --- | --- | --- | --- |
| Setup `gearshape` | `gear` | Keep `gearshape` | Outline toolbar weight; sync coach → `gearshape` |
| Design `pen.toolpath` | `pencil.and.ruler` | `pencil.and.outline` | **Invalid SF name**; Mac drawing metaphor |
| Model `cube.box` | `cube.box` | Keep | Consistent |
| Cut `scissors` | `scissors` | Keep | Consistent |
| Preview `play.circle` | `eye` | Keep `play.circle` on rail; coach may stay `eye` | Preview = simulate/play |
| Machine `printer.tray` | `powerplug` | `cable.connector` | **Invalid SF name**; CNC serial/machine, not print tray |

---

## 2. Global chrome

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| GL-01 | Command palette | ⌘K | 1 | `magnifyingglass` | no | Live: `CommandPaletteView`, `RecipePicker` |
| GL-02 | Clear search | ⌘K / recipes | 1 | `xmark.circle.fill` | no | Live: several |
| GL-03 | Preferences | Menu / chrome | 1 | `gearshape` | no | |
| GL-04 | Help / coach tip | Coach panel | 1 | `questionmark.circle` | no | Coach currently reuses stage icons |
| GL-05 | Dismiss | Sheets / coach | 1 | `xmark.circle.fill` | no | Live: coach, vars |
| GL-06 | More / overflow | Primary toolbars | 1 | `ellipsis.circle` | no | Caps primary at ≤12 |
| GL-07 | Sidebar browser | Window chrome | 1 | `sidebar.left` | no | |
| GL-08 | Inspector | Window chrome | 1 | `sidebar.right` | no | |
| GL-09 | Unsaved / dirty | Status / browser | 1 | `exclamationmark.circle` | no | Today: orange caption text |
| GL-10 | Recipe picker | Setup / global | 1 | `rectangle.stack` | no | Live recipes use `square.grid.2x2`, `textformat.abc`, etc. |
| GL-11 | New job | Setup / File | 1 | `doc.badge.plus` | no | Live: `plus.circle.fill` in `NewJobView` |
| GL-12 | Templates | Setup / File | 1 | `doc.on.doc` | no | Live: `square.grid.2x2.fill` |
| GL-13 | Chevron expand | Lists / menus | 1 | `chevron.right` / `chevron.down` | no | Live: `NewJobView` |
| GL-14 | Filter | Doc vars / lists | 1 | `line.3.horizontal.decrease.circle` | no | Live: `DocumentVariablesPanel` |
| GL-15 | Edit (inline) | Lists | 1 | `pencil` | no | Live: doc vars |
| GL-16 | Density / audit gauge | Dev / prefs | 3 | `gauge.medium` | no | Live: `IconEnforcement` |

---

## 2a. Visibility chips (parity B05)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| VC-01 | Vectors visible | Canvas chips | 1 | `point.topleft.down.to.point.bottomright.curvepath` | no | Same metaphor as browser shapes |
| VC-02 | Bitmaps visible | Canvas chips | 1 | `photo` | no | |
| VC-03 | Toolpaths visible | Canvas chips | 1 | `point.topleft.down.to.point.bottomright.curvepath` | maybe | Or custom toolpath stroke glyph |
| VC-04 | Components visible | Canvas chips | 2 | `cube` | no | |
| VC-05 | Keep-outs visible | Canvas chips | 1 | `hand.raised` / `nosign` | maybe | Prefer clear “forbidden zone” metaphor |

---

## 2b. View chrome (parity B06–B07, Commands view)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| VW-01 | View cube | Canvas overlay | 1 | — | yes | Custom 3-face cube glyph (template SF) |
| VW-02 | View preset Top | View menu / cube | 1 | `square` | maybe | Or labeled cube faces |
| VW-03 | View preset Front | View menu / cube | 1 | `rectangle.portrait` | maybe | |
| VW-04 | View preset Iso | View menu / cube | 1 | `cube` | no | |
| VW-05 | Orthographic | View | 2 | `square.dashed` | maybe | |
| VW-06 | 2D view mode | View | 1 | `square` | no | |
| VW-07 | 3D view mode | View | 1 | `cube` | no | |
| VW-08 | Split 2D+3D | View | 2 | `rectangle.split.2x1` | no | |
| VW-09 | Zoom to fit | View / Design | 1 | `arrow.up.left.and.arrow.down.right` | no | Live canvas: `rectangle.dashed`; CommandID `zoomFit` |
| VW-10 | Zoom in | View / Design | 1 | `plus.magnifyingglass` | no | Live canvas: `plus` |
| VW-11 | Zoom out | View / Design | 1 | `minus.magnifyingglass` | no | Live canvas: `minus` |
| VW-12 | Reset view | View | 1 | `arrow.counterclockwise` | no | CommandID `resetView` |
| VW-13 | Pan | View tool | 1 | `hand.draw` / `arrow.up.and.down.and.arrow.left.and.right` | no | |
| VW-14 | Orbit | 3D view | 2 | `rotate.3d` | no | |
| VW-15 | Multi-sided flip | Model / Setup | 2 | `arrow.triangle.2.circlepath` | no | Live: `MultiSidedView` |

### ⌘K CommandID → glyph (implemented today)

Every `CommandID` in [Commands.swift](../../Sources/ShopPilot/Commands.swift) needs a palette-row icon:

| CommandID | Name | Catalog ID | SF candidate |
| --- | --- | --- | --- |
| `newJob` | New Job | GL-11 / FE-01 | `doc.badge.plus` |
| `openJob` | Open Job… | FE-02 | `folder` |
| `saveJob` | Save Job | FE-03 | `square.and.arrow.down` |
| `exportGcode` | Export G-code | FE-05 | `square.and.arrow.up` |
| `undo` | Undo | FE-10 | `arrow.uturn.backward` |
| `redo` | Redo | FE-11 | `arrow.uturn.forward` |
| `cut` | Cut | FE-12 | `scissors` |
| `copy` | Copy | FE-13 | `doc.on.doc` |
| `paste` | Paste | FE-14 | `doc.on.clipboard` |
| `deleteVector` | Delete Vector | FE-15 | `trash` |
| `zoomFit` | Zoom to Fit | VW-09 | `arrow.up.left.and.arrow.down.right` |
| `zoomIn` | Zoom In | VW-10 | `plus.magnifyingglass` |
| `zoomOut` | Zoom Out | VW-11 | `minus.magnifyingglass` |
| `resetView` | Reset View | VW-12 | `arrow.counterclockwise` |
| `profileTP` | Profile Toolpath | CT-01 | custom / `point.topleft…` |
| `pocketTP` | Pocket Toolpath | CT-02 | custom |
| `drillTP` | Drill Toolpath | CT-03 | custom / `circle.dotted` |
| `vcCarveTP` | V-Carve Toolpath | CT-04 | custom |
| `rough3DTP` | 3D Rough Toolpath | CT-05 | custom |
| `finish3DTP` | 3D Finish Toolpath | CT-06 | custom |
| `connectMachine` | Connect Machine | MC-01 | `cable.connector` |
| `disconnectMachine` | Disconnect Machine | MC-02 | `cable.connector.slash` |
| `jogHome` | Jog to Home | MC-06 | `house` |
| `zeroAxes` | Zero All Axes | MC-07 | `scope` / `plus.viewfinder` |
| `airCut` | Air Cut (Simulate) | MC-19 | `wind` / `airplane` |

---

## 3. Browser tree (left)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| BR-01 | Job / document root | Browser | 1 | `folder.fill` | no | Live: `BrowserPanels` |
| BR-02 | Sheet | Browser | 1 | `doc` | no | Live: `BrowserPanels` |
| BR-03 | Layer visible | Browser | 1 | `eye` | no | Live |
| BR-04 | Layer hidden | Browser | 1 | `eye.slash` | no | Live |
| BR-05 | Shape / vector | Browser | 1 | `square.on.circle` | no | Live |
| BR-06 | Toolpath node | Browser | 1 | `point.topleft.down.to.point.bottomright.curvepath` | no | Live |
| BR-07 | Toolpath dirty | Browser | 1 | `exclamationmark.circle` | no | Badge on BR-06 |
| BR-08 | Component | Browser | 2 | `cube` | no | |
| BR-09 | Folder / group | Browser | 1 | `folder` | no | |
| BR-10 | Library / clipart | Browser | 2 | `books.vertical` / `square.grid.2x2` | no | |
| BR-11 | Machine log | Browser | 1 | `terminal` / `text.alignleft` | no | |
| BR-12 | Add item | Browser / sheets | 1 | `plus` | no | Live: `SheetListView` |
| BR-13 | Duplicate item | Browser / sheets | 1 | `square.on.square` | no | Live: `SheetListView` |
| BR-14 | Delete item | Browser / sheets | 1 | `trash` | no | Live: sheets, console |

---

## 4. Setup stage (primary ≤12)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| SU-01 | Job type single-sided | Setup primary | 1 | `rectangle` | no | |
| SU-02 | Job type double-sided | Setup primary | 2 | `rectangle.on.rectangle` | no | |
| SU-03 | Job type rotary | Setup primary | 2 | `cylinder` / `rotate.3d` | maybe | |
| SU-04 | Stock dimensions | Setup primary | 1 | `ruler` / `arrow.left.and.right` | no | |
| SU-05 | Datum / origin | Setup primary | 1 | `scope` / `plus.viewfinder` | maybe | XY/Z zero mark |
| SU-06 | Machine profile pick | Setup primary | 1 | `cpu` / `memorychip` | no | |
| SU-07 | Units mm | Setup primary | 1 | — | maybe | Text “mm” often clearer than icon |
| SU-08 | Units inch | Setup primary | 1 | — | maybe | Text `"` / “in” |
| SU-09 | Keep-out zone | Setup primary | 1 | `hand.raised` / `nosign` | maybe | Same family as VC-05 |
| SU-10 | Document variables | Setup | 1 | `doc.text.magnifyingglass` | no | Live empty state |
| SU-11 | Onboarding / kickstarter | Setup | 1 | `flag` / `sparkles` | no | |
| SU-12 | More… | Setup primary | 1 | `ellipsis.circle` | no | = GL-06 |

---

## 5. Design stage — primary toolbar (≤12)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| DS-01 | Select | Design primary | 1 | `cursorarrow` | no | Live: `DesignTool.select` |
| DS-02 | Line | Design primary | 1 | `line.diagonal` | no | Live: `DesignTool.line` |
| DS-03 | Polyline | Design primary | 1 | `line.dashed` | no | Live: `DesignTool.polyline` (may move to overflow if budget tight) |
| DS-04 | Rectangle | Design primary | 1 | `rectangle` | no | Live: `DesignTool.rectangle` |
| DS-05 | Circle | Design primary | 1 | `circle` | no | Live: `DesignTool.circle` |
| DS-06 | Text | Design primary | 1 | `textformat` | no | |
| DS-07 | Offset | Design primary | 1 | — | yes | Concentric outline metaphor |
| DS-08 | Boolean | Design primary | 1 | — | yes | Parent for weld/overlap/subtract |
| DS-09 | Import | Design primary | 1 | `square.and.arrow.down` | no | Live hub |
| DS-10 | Node edit | Design primary | 1 | — | yes | Nodes on path |
| DS-11 | Measure | Design primary | 1 | `ruler` | no | |
| DS-12 | More… | Design primary | 1 | `ellipsis.circle` | no | Trim etc. via overflow |

*Primary set must stay ≤12 including More… — prefer Select, Line, Rect, Circle, Text, Offset, Boolean, Import, Node, Measure, More… (polyline in overflow if needed).*

### Design overflow / ⌘K (Wave 2)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| DO-01 | Arc | Design overflow | 2 | `arc` | maybe | |
| DO-02 | Ellipse | Design overflow | 2 | `oval` | no | |
| DO-03 | Polygon | Design overflow | 2 | `hexagon` | no | |
| DO-04 | Star | Design overflow | 2 | `star` | no | |
| DO-05 | Freehand | Design overflow | 2 | `scribble` / `pencil.tip` | no | |
| DO-06 | Fillet | Design overflow | 2 | — | yes | Corner radius |
| DO-07 | Extend | Design overflow | 2 | `arrow.right.to.line` | maybe | |
| DO-08 | Dimensions | Design overflow | 2 | `ruler` | no | Annotative |
| DO-09 | Align | Design overflow | 2 | `align.horizontal.center` | no | |
| DO-10 | Group | Design overflow | 2 | `rectangle.3.group` | no | |
| DO-11 | Ungroup | Design overflow | 2 | `rectangle.3.group.bubble` | maybe | |
| DO-12 | Array copy | Design overflow | 2 | `square.grid.3x3` | no | |
| DO-13 | Circular copy | Design overflow | 2 | `circle.grid.cross` | maybe | |
| DO-14 | Copy along path | Design overflow | 2 | — | yes | |
| DO-15 | Join | Design overflow | 2 | `link` | maybe | |
| DO-16 | Nest parts | Design overflow | 2 | — | yes | Packed shapes |
| DO-17 | Vector validator | Design overflow | 2 | `checkmark.seal` | no | |
| DO-18 | Text on curve | Design overflow | 2 | — | yes | |
| DO-19 | Text to curves | Design overflow | 2 | `text.badge.checkmark` | maybe | |
| DO-20 | Mirror | Design overflow | 2 | `arrow.left.and.right.righttriangle.left.righttriangle.right` | no | |
| DO-21 | Rotate | Design overflow | 2 | `rotate.right` | no | |
| DO-22 | Move | Design overflow | 2 | `arrow.up.and.down.and.arrow.left.and.right` | no | |
| DO-23 | Scale | Design overflow | 2 | `arrow.up.left.and.down.right.magnifyingglass` | maybe | |
| DO-24 | Trim | Design overflow | 2 | — | yes | Interactive trim |
| DO-25 | Trace bitmap | Design overflow | 2 | `photo.on.rectangle.angled` | maybe | |
| DO-26 | Crop bitmap | Design overflow | 2 | `crop` | no | |
| DO-27 | Vector boundary | Design overflow | 2 | — | yes | |
| DO-28 | Distort | Design overflow | 3 | — | yes | |
| DO-29 | Boolean weld | Design overflow | 2 | — | yes | Child of DS-08 |
| DO-30 | Boolean overlap | Design overflow | 2 | — | yes | |
| DO-31 | Boolean subtract | Design overflow | 2 | — | yes | |
| DO-32 | Fit curves | Design overflow | 2 | — | yes | |
| DO-33 | Vector unwrapper | Design overflow | 3 | — | yes | Rotary |

---

## 6. Model stage (Wave 2)

### Primary ≤12

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MD-01 | Select | Model primary | 2 | `cursorarrow` | no | Share DS-01 |
| MD-02 | Shapes | Model primary | 2 | `square.on.circle` | maybe | Opens shape style menu |
| MD-03 | Import 3D | Model primary | 2 | `cube` + badge | maybe | STL/OBJ/3MF |
| MD-04 | Sculpt | Model primary | 2 | — | yes | Brush / clay |
| MD-05 | Combine | Model primary | 2 | — | yes | Parent for modes |
| MD-06 | Zero plane | Model primary | 2 | — | yes | Flat Z plane |
| MD-07 | Position | Model primary | 2 | `move.3d` | maybe | |
| MD-08 | Height scale | Model primary | 2 | `arrow.up.and.down` | no | |
| MD-09 | Bake | Model primary | 2 | `flame` / `square.and.arrow.down.on.square` | maybe | |
| MD-10 | Smooth | Model primary | 2 | — | yes | Soften relief |
| MD-11 | Library | Model primary | 2 | `books.vertical` | no | |
| MD-12 | More… | Model primary | 2 | `ellipsis.circle` | no | |

### Overflow (parity E)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MO-01 | Combine Add | Model overflow | 2 | `plus.square.on.square` | maybe | |
| MO-02 | Combine Subtract | Model overflow | 2 | `minus.square` | maybe | |
| MO-03 | Combine Merge high | Model overflow | 2 | — | yes | |
| MO-04 | Combine Low | Model overflow | 2 | — | yes | |
| MO-05 | Combine Multiply | Model overflow | 3 | — | yes | |
| MO-06 | Shape angled | Model overflow | 2 | — | yes | |
| MO-07 | Shape round | Model overflow | 2 | — | yes | |
| MO-08 | Shape smooth | Model overflow | 2 | — | yes | |
| MO-09 | Shape flat plane | Model overflow | 2 | `square.fill` | maybe | |
| MO-10 | Shape custom | Model overflow | 2 | — | yes | |
| MO-11 | Two-rail sweep | Model overflow | 2 | — | yes | |
| MO-12 | Extrude / weave | Model overflow | 2 | — | yes | |
| MO-13 | Turn / spin | Model overflow | 2 | `rotate.3d` | maybe | |
| MO-14 | Emboss | Model overflow | 2 | — | yes | |
| MO-15 | Offset model | Model overflow | 2 | — | yes | |
| MO-16 | Add draft | Model overflow | 3 | — | yes | |
| MO-17 | Replace below | Model overflow | 3 | — | yes | |
| MO-18 | Texture area | Model overflow | 2 | — | yes | |
| MO-19 | Component from bitmap | Model overflow | 2 | `photo` | maybe | |
| MO-20 | Clear / split | Model overflow | 2 | `scissors` | maybe | |
| MO-21 | Segment | Model overflow | 3 | — | yes | |
| MO-22 | Slice model | Model overflow | 3 | — | yes | |
| MO-23 | Cross-section → vector | Model overflow | 2 | — | yes | |
| MO-24 | Boundary from components | Model overflow | 2 | — | yes | |
| MO-25 | Export STL | Model overflow | 2 | `square.and.arrow.up` | no | |
| MO-26 | Level mirror modes | Model overflow | 2 | `arrow.left.and.right.righttriangle…` | maybe | |

---

## 7. Cut stage — strategies

### Primary ≤12

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| CT-01 | Profile | Cut primary + ⌘K | 1 | — | yes | Outline cut; CommandID `profileTP` |
| CT-02 | Pocket | Cut primary + ⌘K | 1 | — | yes | Clear inside; CommandID `pocketTP` |
| CT-03 | Drill | Cut primary + ⌘K | 1 | `circle.dotted` / `dot.circle` | maybe | CommandID `drillTP` |
| CT-04 | V-Carve | Cut primary + ⌘K | 1 | — | yes | V-bit lettering; CommandID `vcCarveTP` |
| CT-05 | 3D Rough | Cut primary + ⌘K | 1 | — | yes | CommandID `rough3DTP` |
| CT-06 | 3D Finish | Cut primary + ⌘K | 1 | — | yes | CommandID `finish3DTP` |
| CT-07 | Material setup | Cut primary | 1 | `square.stack.3d.up` / `shippingbox` | maybe | |
| CT-08 | Tool database | Cut primary | 1 | `wrench.and.screwdriver` | no | |
| CT-09 | Tabs | Cut primary | 1 | — | yes | Bridge tabs on profile |
| CT-10 | Keep-outs | Cut primary | 1 | (same as SU-09) | maybe | |
| CT-11 | Recalculate | Cut primary | 1 | `arrow.triangle.2.circlepath` | no | Dirty → clean |
| CT-12 | More strategies… | Cut primary | 1 | `ellipsis.circle` | no | |

### 3D strategy variants (Wave 2 — lists in inspector)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| CT-13 | Adaptive rough | Cut / 3D UI | 2 | — | yes | THREED_UI_DESIGN |
| CT-14 | Step-over rough | Cut / 3D UI | 2 | — | yes | |
| CT-15 | Parallel finish | Cut / 3D UI | 2 | — | yes | |
| CT-16 | Scallop finish | Cut / 3D UI | 2 | — | yes | |
| CT-17 | Rest machining | Cut / 3D UI | 2 | — | yes | |

### Overflow strategies / gadgets (Wave 3)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| CO-01 | Quick engrave | Cut overflow | 3 | — | yes | |
| CO-02 | Fluting | Cut overflow | 3 | — | yes | |
| CO-03 | Texture toolpath | Cut overflow | 3 | — | yes | |
| CO-04 | Prism | Cut overflow | 3 | — | yes | |
| CO-05 | Chamfer | Cut overflow | 3 | — | yes | |
| CO-06 | Moulding | Cut overflow | 3 | — | yes | |
| CO-07 | Photo V-Carve | Cut overflow | 3 | `photo` | maybe | |
| CO-08 | Sketch carving | Cut overflow | 3 | `pencil.tip` | maybe | |
| CO-09 | Inlay pocket / plug | Cut overflow | 3 | — | yes | |
| CO-10 | V-carve inlay | Cut overflow | 3 | — | yes | |
| CO-11 | Thread milling | Cut overflow | 3 | — | yes | |
| CO-12 | Array copy TP | Cut overflow | 3 | `square.grid.3x3` | no | |
| CO-13 | Merged toolpath | Cut overflow | 3 | `arrow.triangle.merge` | maybe | |
| CO-14 | Tiling manager | Cut overflow | 3 | `rectangle.split.2x2` | maybe | |
| CO-15 | Laser cut / fill | Cut overflow | 3 | — | yes | Deferred v1 laser |
| CO-16 | Laser picture | Cut overflow | 3 | — | yes | |
| CO-17 | Rounding gadget | Cut overflow | 3 | — | yes | |
| CO-18 | Keyhole gadget | Cut overflow | 3 | — | yes | |
| CO-19 | Drag knife | Cut overflow | 3 | — | yes | |
| CO-20 | Wrapped fluting | Cut overflow | 3 | — | yes | Rotary |
| CO-21 | Wrapped spiral | Cut overflow | 3 | — | yes | |
| CO-22 | Celtic weave | Cut overflow | 3 | — | yes | |
| CO-23 | Post processor | Cut / shop | 1 | `gearshape.2` | no | |
| CO-24 | Job sheet | Cut / export | 2 | `doc.richtext` | no | |
| CO-25 | Save toolpaths | Cut | 1 | `square.and.arrow.down` | no | |
| CO-26 | Vector selector | Cut inspector | 1 | `checkmark.circle` | maybe | Protocol `iconName` in Core — unassigned |

---

## 8. Preview stage

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PV-01 | Simulate play | Preview primary | 1 | `play.fill` | no | |
| PV-02 | Simulate pause | Preview primary | 1 | `pause.fill` | no | |
| PV-03 | Simulate stop | Preview primary | 1 | `stop.fill` | no | |
| PV-04 | Draft quality | Preview primary | 1 | `circle` | maybe | Vs filled = final |
| PV-05 | Final quality | Preview primary | 1 | `circle.fill` | maybe | |
| PV-06 | Material appearance | Preview primary | 1 | `paintpalette` / `cube.transparent` | maybe | |
| PV-07 | Time estimate | Preview primary | 1 | `clock` | no | |
| PV-08 | Proof image / snapshot | Preview primary | 1 | `camera` | no | |
| PV-09 | Wireframe overlay | Preview | 2 | `square.grid.3x3` / `point.3.connected…` | maybe | |
| PV-10 | Ghost diff | Preview | 2 | `rectangle.on.rectangle.dashed` | maybe | Old vs new |
| PV-11 | Continue to Machine | Preview | 1 | `arrow.right.circle` / `cable.connector` | no | |
| PV-12 | More… | Preview primary | 1 | `ellipsis.circle` | no | |

---

## 9. Machine stage (safety-critical)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| MC-01 | Connect | Machine primary + ⌘K | 1 | `cable.connector` | no | Text-only today |
| MC-02 | Disconnect | Machine + ⌘K | 1 | `cable.connector.slash` | no | Text-only today |
| MC-03 | Connection status idle | Status strip | 1 | `circle.fill` | no | Colored dot today |
| MC-04 | Connection status run | Status strip | 1 | `circle.fill` | no | Green |
| MC-05 | Connection status alarm | Status strip | 1 | `exclamationmark.triangle.fill` | no | Red family |
| MC-06 | Port / profile | Machine | 1 | `cable.connector` / `cpu` | no | |
| MC-07 | Jog +Y | Jog pad | 1 | `arrow.up` | no | Live: `MachineConnection` |
| MC-08 | Jog −Y | Jog pad | 1 | `arrow.down` | no | Live |
| MC-09 | Jog −X | Jog pad | 1 | `arrow.left` | no | Live |
| MC-10 | Jog +X | Jog pad | 1 | `arrow.right` | no | Live |
| MC-11 | Jog +Z / −Z | Jog pad | 1 | `arrow.up` / `arrow.down` | no | Live (Z column) |
| MC-12 | Home | Jog + ⌘K | 1 | `house.fill` | no | Live; CommandID `jogHome` → `house` OK |
| MC-13 | Zero X | Machine | 1 | — | maybe | Text “X0” often clearer |
| MC-14 | Zero Y | Machine | 1 | — | maybe | |
| MC-15 | Zero Z | Machine | 1 | — | maybe | |
| MC-16 | Zero all axes | Machine + ⌘K | 1 | `scope` / `plus.viewfinder` | maybe | CommandID `zeroAxes` |
| MC-17 | Stream Start | Machine | 1 | `play.fill` | no | Live |
| MC-18 | Stream Stop | Machine | 1 | `stop.fill` | no | Live |
| MC-19 | Stream Resume | Machine | 1 | `play.fill` | no | Live (after hold) |
| MC-20 | Hold | Fixed safety chrome | 1 | `pause.circle.fill` | no | Live; **red**; always visible when connected |
| MC-21 | Reset | Fixed safety chrome | 1 | `arrow.counterclockwise.circle.fill` | no | Live; **red**; always visible when connected |
| MC-22 | Console / TX-RX | Machine | 1 | `terminal` / `text.alignleft` | no | Toggle text today |
| MC-23 | Send console line | Console | 1 | `arrow.up.circle.fill` | no | Live |
| MC-24 | Clear console | Console | 1 | `trash` | no | Live |
| MC-25 | Preflight checklist | Machine | 1 | `checkmark.seal.fill` | no | Live |
| MC-26 | Preflight item pending | Checklist | 1 | `circle` | no | Live |
| MC-27 | Preflight item passed | Checklist | 1 | `checkmark.circle.fill` | no | Live |
| MC-28 | Run after preflight | Machine | 1 | `play.fill` | no | Live |
| MC-29 | Spindle on | Machine | 1 | — | yes | Explicit only; no auto on connect |
| MC-30 | Spindle off | Machine | 1 | — | yes | Slash variant of MC-29 |
| MC-31 | Coolant on | Machine | 2 | `drop` | no | Explicit only |
| MC-32 | Coolant off | Machine | 2 | `drop.slash` | no | |
| MC-33 | Air cut | Machine + ⌘K | 1 | `wind` | maybe | CommandID `airCut` |
| MC-34 | Soft-limit warning | Machine | 1 | `exclamationmark.triangle` | no | |
| MC-35 | Alarm banner | Machine | 1 | `exclamationmark.octagon.fill` | no | **red** |

---

## 10. File / edit / import (standard Mac)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| FE-01 | New | File / ⌘K | 1 | `doc.badge.plus` | no | |
| FE-02 | Open | File / ⌘K | 1 | `folder` | no | |
| FE-03 | Save | File / ⌘K | 1 | `square.and.arrow.down` | no | macOS Save often uses this |
| FE-04 | Save As | File | 1 | `square.and.arrow.down.on.square` | no | |
| FE-05 | Export G-code | File / ⌘K | 1 | `square.and.arrow.up` | no | |
| FE-06 | Import choose file | Import hub | 1 | `square.and.arrow.down` | no | Live |
| FE-07 | Import success | Import hub | 1 | `checkmark.circle.fill` | no | Live |
| FE-08 | Import failure | Import hub | 1 | `exclamationmark.triangle.fill` | no | Live |
| FE-09 | Add imported / discard | Import hub | 1 | `plus.circle.fill` / `xmark.circle.fill` | no | Live |
| FE-10 | Undo | Edit / Design | 1 | `arrow.uturn.backward` | no | Live canvas |
| FE-11 | Redo | Edit / Design | 1 | `arrow.uturn.forward` | no | Live canvas |
| FE-12 | Cut (clipboard) | Edit | 1 | `scissors` | no | Distinct from Cut stage |
| FE-13 | Copy | Edit | 1 | `doc.on.doc` | no | |
| FE-14 | Paste | Edit | 1 | `doc.on.clipboard` | no | |
| FE-15 | Delete | Edit | 1 | `trash` | no | |
| FE-16 | Variable validated | Doc vars | 1 | `checkmark.seal` | no | Live Core UI |
| FE-17 | Add variable | Doc vars | 1 | `plus.circle.fill` | no | Live |

### Recipes (live)

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| RC-01 | Calibration / person | Recipe list | 1 | `person.crop.circle` | no | Live: `RecipePicker` |
| RC-02 | Grid / nest recipe | Recipe list | 1 | `square.grid.2x2` | no | Live |
| RC-03 | Sign / lettering | Recipe list | 1 | `textformat.abc` | no | Live: Sign recipe |
| RC-04 | Custom / new recipe | Recipe list | 1 | `plus.circle` | no | Live |

---

## 11. Status / empty / risk chips

| ID | Name | Surface | Wave | SF candidate | Custom? | Notes / Live |
| --- | --- | --- | --- | --- | --- | --- |
| STT-01 | Success | Global | 1 | `checkmark.circle.fill` | no | Live many |
| STT-02 | Warning | Global | 1 | `exclamationmark.triangle.fill` | no | Live |
| STT-03 | Error / alarm | Global / Machine | 1 | `exclamationmark.octagon.fill` | no | Red |
| STT-04 | Needs recalculation | Inspector / browser | 1 | `exclamationmark.circle` | no | Risk chip |
| STT-05 | Empty — no results | ⌘K | 1 | `magnifyingglass` | no | Live |
| STT-06 | Empty — doc vars | Setup | 1 | `doc.text.magnifyingglass` | no | Live |
| STT-07 | Empty — Design CTA | Design | 1 | `pencil.and.outline` | no | Stage empty state |
| STT-08 | Empty — Cut CTA | Cut | 1 | `scissors` | no | |
| STT-09 | Empty — Preview CTA | Preview | 1 | `play.circle` | no | |
| STT-10 | Empty — Machine CTA | Machine | 1 | `cable.connector` | no | |
| STT-11 | Progress / streaming | Machine | 1 | ProgressView | no | System spinner |
| STT-12 | Audit pass / fail | IconEnforcement | 3 | `checkmark.shield.fill` / `exclamationmark.triangle.fill` | no | Live |

---

## Wave summary

| Wave | Scope | Approx. rows |
| --- | --- | --- |
| **1** | Brand, stage rail, global chrome, visibility/view, browser, Setup/Design/Cut/Preview/Machine primaries, safety chrome, file/edit, live CommandIDs, status | Ship-first |
| **2** | Model primary + overflow, Design overflow P0–P1, 3D strategy variants, multi-sided, job sheet | Studio3D / depth |
| **3** | Specialty toolpaths, gadgets, laser, rotary advanced, density-audit chrome | Later parity |

### Custom-needed priority (generate as SF templates later)

Highest value customs (no good stock SF metaphor):

1. **CT-01–CT-06** — Profile, Pocket, Drill (if `circle.dotted` insufficient), V-Carve, 3D Rough, 3D Finish  
2. **DS-07, DS-08, DS-10, DO-24, DO-29–31** — Offset, Boolean family, Node edit, Trim  
3. **VW-01** — View cube  
4. **MD-04–MD-06, MD-10** — Sculpt, Combine, Zero plane, Smooth  
5. **CT-09** — Tabs  
6. **MC-29–MC-30** — Spindle on/off (shop-clear, not generic power)  
7. **APP-01 / APP-02** — App + document icons  

---

## Live control crosswalk

Ensures every current iconized (or icon-owed) control maps to a catalog ID.

| Source | Control / symbol | Catalog ID |
| --- | --- | --- |
| `StageEnum` | stage icons | ST-01…ST-06 |
| `ContentView` | `lock.fill` | ST-07 |
| `BrowserPanels` | folder/doc/eye/shape/toolpath | BR-01…BR-06 |
| `DesignCanvasView` | DesignTool icons + undo/redo/zoom | DS-01…DS-05, FE-10/11, VW-09…11 |
| `Commands.swift` | all CommandIDs | see §2b table |
| `CommandPaletteView` | search / clear / empty | GL-01, GL-02, STT-05 |
| `MachineConnection` | jog, home, play/stop, hold, reset, console, preflight | MC-07…MC-28, MC-23/24 |
| `ImportHubView` | format + result + add/discard | APP-04/05, FE-06…09 |
| `NewJobView` | plus / templates / chevron | GL-11, GL-12, GL-13 |
| `RecipePicker` / `SignRecipeManager` | recipe icons | RC-01…04, GL-01/02 |
| `DocumentVariablesPanel` + Core UI | filter/add/edit/trash/empty/seal | GL-14/15, FE-16/17, STT-06, BR-14 |
| `SheetListView` | trash / duplicate / plus | BR-12…14 |
| `CoachPanelView` | stage tip icons + dismiss | GL-04/05 + stage audit |
| `IconEnforcement` | audit UI | GL-16, STT-12 |
| `MultiSidedView` | flip | VW-15 |
| `VectorSelector` | `iconName` protocol | CO-26 (unassigned) |

### Text-only today (need icons when chrome ships)

| Control | Catalog ID |
| --- | --- |
| Connect / Disconnect | MC-01, MC-02 |
| Zero X/Y/Z | MC-13…15 |
| Show TX/RX toggle | MC-22 |
| Cut stage Generate Profile / Load Fixture / Send to Machine | CT-01, FE-06, MC-17 / PV-11 |
| Preview Continue to Machine | PV-11 |
| Spindle / coolant | MC-29…32 |
| ⌘K command rows (no per-command icons yet) | §2b CommandID table |

---

## Out of scope (this document)

- Generating PNG/SVG/PDF or Icon Composer assets  
- Editing Swift call sites (inventory first; symbol swaps tracked in stage audit)  
- Copying third-party icon shapes  

## Next steps (after this inventory)

1. Replace `pen.toolpath` / `printer.tray` with audited SF names in `StageEnum` (+ sync coach).  
2. Add `icon` (or `systemImage`) on `CommandID` for ⌘K rows.  
3. Commission Wave 1 **custom** glyphs (toolpath strategies + Design CAD ops + app icon).  
4. Keep primary toolbars ≤12 via IconEnforcement when Design/Cut/Model toolbars land.
