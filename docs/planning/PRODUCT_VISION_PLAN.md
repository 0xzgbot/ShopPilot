# ShopPilot Studio — Reimagined for Mac

**Document type:** Master product + team execution plan  
**Source studied:** reference V12.0 user guide (public docs; full TOC + workflow + 3D system + What’s New V12)  
**Date:** 2026-07-28  
**Product family:** **ShopPilot**  
**Scope:** Every professional-grade capability, reorganized for Mac-native clarity; plus native machine control (the incumbent’s gap)

---

## 1. North star

**The reference proved the workflow.** The CNC job is:

> **Material → Vectors/Bitmaps → 3D Components → Toolpaths → Preview → Post → Cut**

That logic is correct and must not be “simplified away.”  
**What we reimagine is the *interface density*, not the *capability set*.**

### Promise

> A Mac-native creative CNC suite that can do **everything the incumbent does** — signs, inlays, 3D relief, rotary, laser, production nesting — while feeling like **Final Cut / Figma / Lightroom**: one calm canvas, progressive disclosure, search-first power tools, and **Run on Machine** without leaving the app.

### Strategic advantages over the incumbent (Mac)

| Incumbent (Windows-centric) | ShopPilot (Mac reimagined) |
| --- | --- |
| Design ↔ Toolpath tab thrash | **Stage rail** (Setup → Design → Model → Toolpaths → Preview → Machine) |
| Dense left icon grids | **Primary tools + overflow + ⌘K command palette** |
| Separate VTransfer-ish machine hop | **Native ShopPilot Control** (serial / GRBL / FluidNC) in-app |
| Forms remember last values | Forms + **smart defaults from machine + material + tool DB** |
| Help via `?` icons | **Context coach** (inline tips + video moments + validation) |
| Clipart / cloud accounts | Optional library; **local-first** default |
| Single-app bloat perception | **Modes + recipes** hide advanced until needed |

---

## 2. Product architecture (family)

```
┌─────────────────────────────────────────────────────────────┐
│                     ShopPilot.app (SwiftUI)                 │
├──────────────┬──────────────────┬───────────────────────────┤
│ Design Core  │ Toolpath Engine  │ Machine Runtime           │
│ vectors, 3D  │ strategies, sim  │ serial stream, jog, hold  │
│ components   │ posts, tools DB  │ profiles, keep-outs live  │
├──────────────┴──────────────────┴───────────────────────────┤
│ Shared: Job document, sheets, materials, undo, plugins      │
└─────────────────────────────────────────────────────────────┘
```

| Module | Responsibility | Reference analog |
| --- | --- | --- |
| **Job & Sheets** | Single/double/rotary stock, multi-sheet, templates, variables | Job Setup, Sheet Management |
| **Design 2D** | Vectors, text, bitmaps, layers, nest, plate | Drawing tab |
| **Model 3D** | Components, levels, combine, sculpt, import | Modeling + Component tree |
| **Toolpaths** | All strategies, templates, tiling, merge | Toolpaths tab |
| **Preview** | Material block sim, time estimate, proof images | Preview Toolpaths |
| **Tools & Posts** | Tool DB, materials, machines, post editor | Tool Database, Post Processors |
| **Machine** | Connect, zero, stream, hold, console | VTransfer + sender (ours is first-class) |
| **Library** | Clipart, gadgets/recipes, community packs | Clipart + Gadgets |
| **Laser** | Cut/fill, picture; laser posts | Laser Module |

**Document format (own):** `.shoppilot` (package: JSON/SQLite + media).  
**Import:** DXF, DWG, EPS, AI, PDF, SVG, SKP, STL/OBJ/3MF, bitmaps, optional CRV/CRV3D research later (no illegal reverse-engineering of proprietary formats without clean-room).

---

## 3. UX doctrine — full power, zero clutter

### 3.1 The Stage Rail (primary navigation)

Replace dual-tab thrash with a **persistent horizontal stage**:

```
[ Setup ] → [ Design ] → [ Model ] → [ Cut ] → [ Preview ] → [ Machine ]
```

- Stages are **modes**, not separate apps. Document state is continuous.
- **Cut** = toolpath creation (the reference’s “Toolpaths”).
- **Machine** = live control (our differentiator).
- Keyboard: `1…6` switch stages; `Space` pan; standard Mac conventions.
- **Figma-like:** advanced panels collapse; selection drives inspector.

### 3.2 Three chrome layers only

| Layer | Always visible? | Contents |
| --- | --- | --- |
| **A. Canvas** | Yes | Unified 2D/3D view (toggle + split); view cube; visibility chips |
| **B. Inspector** | When selection/tool | Single right panel: context properties only |
| **C. Browser** | Optional left | Layers / Components / Toolpaths / Sheets (tabs inside one browser) |

**No permanent 80-icon wall.** Instead:

1. **Primary toolbar** (8–12 tools for current stage).  
2. **More…** overflow (grouped).  
3. **⌘K Command Palette** — every reference command discoverable by name.  
4. **Recipes** — one-click multi-step (e.g. “V-Carve Inlay pair”, “Sign: text + border + pocket”).

### 3.3 Progressive disclosure rules

| Frequency | Where it lives |
| --- | --- |
| Everyday (profile, pocket, vcarve, text, import) | Primary toolbar + empty-state CTAs |
| Occasional (nest, fluting, prism, photo vcarve) | Overflow + palette + “Specialized cuts” |
| Rare/power (post editor, multiply combine, gadgets) | Settings / Developer / Advanced pack (still full-featured) |
| Expert (POST language blocks, jet sections) | Post Studio (separate window) |

### 3.4 Job Recipes (new product idea)

On **New Job**, pick a recipe instead of blank form density:

| Recipe | Pre-fills |
| --- | --- |
| Sign / plaque | Single side, V-carve + profile defaults |
| Cabinet part | Profile outside, pockets, drill |
| 3D relief | Model stage emphasized, rough+finish TP |
| Inlay (V or pocket) | Dual sheet workflow + linked toolpaths |
| Rotary column | Rotary job + wrap layout helpers |
| Laser cut | Laser strategies, laser post |
| Production nest | Nest + multi-sheet + job sheet |
| Calibration | reference-style square/circle/star test |

Every recipe still opens the **same full app** — nothing is locked away permanently.

### 3.5 Smart inspector pattern

Toolpath forms follow the reference’s top→bottom logic, but:

1. **Essentials** always open (depth, tool, vectors, cut side).  
2. **Passes / tabs / ramps / leads** collapsed.  
3. **Advanced** (start points, order, spiral, etc.) behind disclosure.  
4. Live **risk chips**: “plunges into keep-out”, “tool too large for corners”, “needs recalculation”.

### 3.6 Reference principles we keep (non-negotiable)

From reference workflow docs:

1. **Toolpaths do not auto-mutate when art moves** — explicit recalculate (safety + predictability).  
2. Toolpaths **remember source vectors** for re-edit.  
3. **Preview uses same data as export** (trust model).  
4. **Post processor is the translation layer** after strategy calc.  
5. **Composite model** = Components on Levels with combine modes.  
6. Multi-sheet, double-sided, rotary as first-class job types.

### 3.7 Mac-native interactions

- Trackpad: pinch zoom, two-finger rotate in 3D, Force Click measure.  
- Continuity: AirDrop toolpath files; optional iPhone camera → Sketch Carving source.  
- Metal for preview simulation & heightfield composite.  
- System fonts + user fonts; SF Symbols for tool icons.  
- Dark shop theme + light studio theme.  
- Fullscreen canvas; Stage Manager friendly.

---

## 4. Complete reference feature inventory → ShopPilot mapping

> **Parity rule:** If it exists in the reference V12 docs, it must appear in our capability matrix.  
> **UX rule:** It need not appear as a permanent top-level icon.

Legend: **P0** MVP parity slice · **P1** full creative · **P2** production/power · **P3** specialist

### 4.1 Getting started & job system

| Reference feature | ShopPilot | Pri | UX placement |
| --- | --- | --- | --- |
| Kickstarter / first-run | Onboarding + Machine Wizard | P0 | First launch |
| License / V&Co sign-in | Local license / optional account | P2 | Settings (local-first) |
| Online machine configuration | Machine catalog + profiles | P0 | Setup → Machine |
| Manual machine configuration | Profile editor | P0 | Setup |
| Job Setup single-sided | Stock wizard | P0 | Setup |
| Job Setup double-sided | Flip/registration workflow | P1 | Setup → job type |
| Job Setup rotary | Cylinder params, Z origin center/surface | P1 | Setup → job type |
| Edit Sheet (single/double/rotary) | Sheet inspector | P1 | Browser → Sheets |
| Multi-sheet management | Sheet dropdown + browser | P1 | Top bar |
| Job templates (.crvt analog) | Template library | P1 | New from template |
| Document variables | Variables panel | P2 | Advanced |
| Calculation edit boxes | Eval in numeric fields | P0 | Everywhere |
| Options dialog | Preferences | P0 | Settings |
| Migration dialog | Version migration | P2 | On open |
| Crash handling | Crash reporter + recovery | P1 | System |

### 4.2 Views & interface

| Reference feature | ShopPilot | Pri | UX placement |
| --- | --- | --- | --- |
| 2D design window | Canvas 2D mode | P0 | Canvas |
| 3D view | Canvas 3D mode | P0 | Canvas |
| Simultaneous 2D+3D | Split view | P1 | View menu |
| Design vs Toolpath layouts | Stage rail auto-layout | P0 | Stages |
| Auto-hide tool pages | Inspector auto-collapse | P0 | Chrome |
| View toolbar visibility toggles | Visibility chips | P0 | Canvas top |
| View control / view cube | View cube + presets | P0 | 3D canvas |
| Orthographic mode | Ortho toggle | P1 | View |
| Drawing in 3D view | Tools work in 3D | P1 | Design stage |
| Vectors overlaid in 3D | Toggle | P1 | Visibility |
| Multi-sided view | Top/bottom composite | P1 | Double-sided jobs |
| Layers quick dropdown | Layer control | P0 | Top bar |
| Sheet dropdown | Sheet control | P1 | Top bar |
| Components/levels dropdown | Level control | P1 | Top bar |
| Help prompts / ? | Context coach | P0 | Inspector footer |
| Keyboard shortcuts | Full map + customizable | P0 | Settings |
| Right-click menus | Context menus | P0 | Canvas |
| Unified import (V12) | One Import… | P0 | File / toolbar |

### 4.3 2D design — create

| Reference feature | ShopPilot | Pri | UX |
| --- | --- | --- | --- |
| Draw line/polyline | Line | P0 | Primary |
| Draw arc | Arc | P0 | Primary |
| Draw circle | Circle | P0 | Primary |
| Draw ellipse | Ellipse | P0 | More… |
| Draw rectangle | Rect | P0 | Primary |
| Draw polygon | Polygon | P1 | More… |
| Draw star | Star | P1 | More… |
| Freehand drawing | Pencil | P1 | Primary optional |
| Create text | Text | P0 | Primary |
| Text on a curve | Type on path | P1 | Text overflow |
| Convert text to curves | Outline | P0 | Text menu |
| Single-stroke engraving fonts | Engraving font pack | P1 | Font picker |
| Dimensions | Dim tools | P1 | Annotate |
| Create fillets | Fillet | P0 | Edit primary |
| Extend vectors | Extend | P1 | Node/edit |
| Offset vectors | Offset | P0 | Primary |
| Vector boundary | Boundary | P1 | More… |
| Vector texture | Hatch/texture vectors | P2 | Specialized |
| Plate production | Multi-label plate | P2 | Recipes |

### 4.4 2D design — edit & organize

| Reference feature | ShopPilot | Pri | UX |
| --- | --- | --- | --- |
| Selection / interactive selection | Select | P0 | Default tool |
| Vector selection mode | Select filter | P1 | Inspector |
| Node editing mode | Node edit | P0 | Double-click / N |
| Transform mode | Move/scale/rotate handles | P0 | Selection |
| Move selection | Move | P0 | |
| Set size | Size dialog | P0 | Inspector |
| Rotate | Rotate | P0 | |
| Mirror | Mirror | P0 | |
| Align tools | Align | P0 | Primary when multi-select |
| Group / ungroup | Group | P0 | ⌘G |
| Array copy | Rectangular array | P0 | |
| Circular copy | Polar array | P1 | |
| Copy along vectors | Path array | P1 | |
| Join open vectors | Join | P0 | |
| Join with straight / smooth / move endpoints | Join variants | P0–P1 | Join menu |
| Weld / overlap / subtract vectors | Boolean set | P0 | Primary |
| Trim objects / interactive trim | Trim | P0 | |
| Fit curves to vectors | Simplify/fit | P1 | |
| Distort object | Envelope distort | P2 | Advanced |
| Nest parts | Nest | P1 | Design → Nest |
| Vector validator | Validate | P1 | Pre-cut checklist |
| Vector unwrapper | Unwrap for rotary | P1 | Rotary helpers |
| Measure / inspect | Measure | P0 | |
| Layers management | Layer browser | P0 | Browser |
| Import vectors/bitmaps | Import | P0 | |
| Trace bitmap | Image trace | P0 | |
| Edit picture / crop bitmap | Image tools | P1 | |
| SketchUp import | SKP import | P2 | Import |
| PDF export | Export PDF | P1 | Share |
| Undo / redo / cut / copy / paste | Standard | P0 | |

### 4.5 3D model system (the incumbent’s core differentiator)

| Reference feature | ShopPilot | Pri | UX |
| --- | --- | --- | --- |
| Components + Levels + tree | Scene / Component browser | P0 | Browser → Model |
| Composite model | Live heightfield composite | P0 | 3D view |
| Combine modes: Add, Subtract, Merge(High), Low, Multiply | Combine control | P0 | Inspector chips + visual |
| Dynamic props: height scale, tilt, fade | Component props | P0 | Inspector |
| Level mirror modes (8) | Symmetry level modes | P1 | Level menu |
| Level clipping | Clip | P2 | Advanced |
| Create shape — angled / round / smooth / flat / custom | Shape tools | P0 | Model primary (V12 split tools) |
| Two-rail sweep | Sweep | P1 | Model more |
| Extrude and weave | Extrude/weave | P1 | |
| Turn and spin | Lathe-ish modeling | P1 | Rotary+Model |
| Emboss component | Emboss | P1 | |
| Sculpting | Sculpt brushes | P1 | Fullscreen sculpt mode |
| Smooth components | Smooth | P1 | |
| Scale model height | Height | P0 | |
| Offset model | Offset | P1 | |
| Add draft | Draft | P2 | |
| Replace below | Replace below | P2 | |
| Create zero plane | Zero plane | P0 | |
| Create texture area | Texture region | P1 | |
| Component from bitmap | Height from image | P0 | |
| Component from visible model | Bake visible | P1 | |
| Baking components | Bake | P1 | |
| Clear / split components | Split | P1 | |
| Import 3D model (flat/double) | Import orient wizard | P0 | |
| Import 3D for rotary | Rotary orient | P1 | |
| Position imported model | Position | P0 | |
| 3D segmenting | Segment | P2 | |
| Slice model | Slice | P2 | |
| Cross-section → vector | Cross section | P1 | V12 tool |
| Vector boundary from components | Silhouette | P1 | |
| Export STL | Export mesh | P0 | |
| Clipart tab / library | Library panel | P1 | Optional pack |

### 4.6 Toolpaths (full strategy set)

#### Everyday (primary “Cut” stage)

| Strategy | Pri | Notes |
| --- | --- | --- |
| 2D Profile | P0 | Outside/inside/on, tabs, ramps, climb/conventional |
| Pocketing | P0 | Clearance, stepover, finishing pass |
| Drilling | P0 | Peck options |
| V-Carve | P0 | Flat depth, start depth, tool combo |
| Material setup (flat) | P0 | |
| Preview toolpaths | P0 | |
| Save toolpaths / post | P0 | |
| Toolpath tree list | P0 | Browser |
| Edit / duplicate / delete / recalculate | P0 | |
| Toolpath tabs (holds) | P0 | Profile |
| Vector selector | P0 | |
| Estimating machining times | P0 | Summary |

#### Creative / specialty

| Strategy | Pri | UX group |
| --- | --- | --- |
| Quick engraving | P1 | Engrave |
| Fluting | P1 | Decorative |
| Texture toolpath | P1 | Decorative |
| Prism carving | P1 | Decorative |
| Chamfer | P1 | Edges |
| Moulding / extruded profile | P1 | Profiles |
| Photo V-Carve | P1 | Image |
| Sketch carving (V12) | P1 | Image |
| Inlay (pocket + plug) | P1 | Inlay recipe |
| V-carve inlay (V12) | P1 | Inlay recipe |
| Female inlay pocket | P1 | Inlay |
| Thread milling | P2 | Mechanical |
| 3D rough | P0 (if 3D) | 3D group |
| 3D finish | P0 (if 3D) | 3D group |
| Array copy toolpath | P1 | Production |
| Merged toolpath | P1 | Production |
| Toolpath templates load/save | P1 | Templates |
| Toolpath tiling manager | P2 | Large stock |
| Keep-out zones (V12) | P0 | Safety — Setup + live Machine |
| Laser cut and fill | P1 | Laser pack |
| Laser picture | P1 | Laser pack |

#### Gadgets (first-party recipes, not random scripts)

| Gadget | Pri | Implementation |
| --- | --- | --- |
| Rounding toolpath | P1 | Recipe + strategy helper |
| Keyhole toolpath | P1 | Recipe |
| Drag knife | P2 | Strategy pack |
| Wrapped fluting / spiral layout | P1 | Rotary helpers |
| Celtic weave creator | P2 | Design generator |
| Job setup sheet editor | P1 | Shop docs |

### 4.7 Tools, machines, posts, shop docs

| Reference feature | ShopPilot | Pri |
| --- | --- | --- |
| Tool database | Tools library | P0 |
| Custom naming variables | Naming templates | P2 |
| Remote / cloud tool DB | Optional sync | P3 |
| Material management | Materials library | P0 |
| Machine configuration management | Machines library | P0 |
| Search machine online | Catalog download | P1 |
| Post-processor management | Posts library | P0 |
| Post-processor content / editing | **Post Studio** | P2 |
| Post change log | Version notes | P2 |
| POST_BASE migration | Post migrator | P3 |
| Save toolpaths | Export G-code | P0 |
| Create job sheet | PDF/print setup sheet | P1 |
| PDF export design | Export | P1 |

### 4.8 Rotary (full advanced path)

| Feature | Pri |
| --- | --- |
| Rotary job creation (Z origin center/surface, orientation) | P1 |
| Wrapped 2D toolpaths | P1 |
| Spiral toolpaths | P1 |
| Simple rotary modelling with 2D TP | P1 |
| 3D rotary modelling (clipart on cylinder, taper, turn, cross-section) | P2 |
| Advanced spiral/twisted modelling | P2 |
| Import full-3D / flat models into rotary | P2 |
| Unwrapper | P1 |

### 4.9 Modules & machine link

| Feature | Pri | Notes |
| --- | --- | --- |
| Laser module | P1 | Strategies + laser posts |
| Laser post adaptation guide | P2 | Docs + Post Studio |
| VTransfer analog | **P0 integrated** | **Machine stage** — not a separate utility |
| Imported 3D toolpath files | P2 | External TP import |
| Gadgets system | P1 | Sandboxed recipes (not arbitrary unsafe scripts by default) |

### 4.10 Beyond the incumbent (must-build differentiators)

| Idea | Why | Pri |
| --- | --- | --- |
| **Native machine control** | End-to-end Mac shop | P0 |
| **Pre-flight checklist** | Air-cut, zero, tool, hold-downs (from the reference’s own run guide) | P0 |
| **Live keep-outs** | Sync toolpath rapids + machine awareness | P1 |
| **Command palette** | Discover 200 tools without clutter | P0 |
| **AI assist (optional)** | Suggest strategy, feeds, trace cleanup — offline-capable | P2 |
| **Collaboration** | Share `.shoppilot` + proof renders | P2 |
| **Versioned toolpaths** | Diff recalculation | P2 |
| **Material library with feeds** | Safer than blind defaults | P0 |
| **Touch bar / iPad sidecar later** | Pendant UI | P3 |

---

## 5. Information architecture (clean UI wire)

```
┌─ Stage rail ────────────────────────────────────────────────────────┐
│ Setup │ Design │ Model │ Cut │ Preview │ Machine          [⌘K] [•] │
├─ Browser (optional) ─┬─ Canvas ─────────────────────┬─ Inspector ──┤
│ Sheets               │                             │ Essentials   │
│ Layers               │     2D / 3D / Split         │ ───────────  │
│ Components           │     View cube · chips       │ Advanced ▸   │
│ Toolpaths            │                             │ Coach tips   │
│ Library              │                             │              │
└──────────────────────┴─────────────────────────────┴──────────────┘
```

**Empty states that teach:**

- Setup: “Define your stock — this is your real board.”  
- Design: “Import or draw vectors toolpaths can follow.”  
- Model: “Stack components like a relief collage.”  
- Cut: “Pick a strategy — Profile for cut-out, V-Carve for letters…”  
- Preview: “This is what the machine will remove.”  
- Machine: “Connect, set zero, air-cut, then run.”

---

## 6. Technical architecture (team-executable)

### 6.1 Stack recommendation

| Layer | Choice | Rationale |
| --- | --- | --- |
| App shell | SwiftUI macOS 14+ | User direction; native |
| Geometry kernel | C++/Rust core (vectors, offset, boolean) + Swift bridge | Performance; testability |
| 3D composite | Heightfield + optional mesh; Metal | reference-like relief speed |
| Toolpath engine | Separate compute worker process | Don’t freeze UI |
| Simulation | Voxel/heightfield material remove | Preview trust |
| Serial | Existing ShopPilot Control module | Unified product |
| Persistence | Document package + autosave | Crash safety |
| Plugins/recipes | Declarative JSON/Lua sandbox later | Gadgets without malware |

### 6.2 Core data model (conceptual)

```
Job
 ├─ units, variables
 ├─ MachineProfile ref
 ├─ Sheets[] (single | double | rotary params)
 │    ├─ Layers[] → Vectors, Bitmaps, Text
 │    ├─ Levels[] → Components (combine, mirror)
 │    └─ Toolpaths[] (strategy params, cached path, dirty flag)
 ├─ Tools used snapshot
 └─ KeepOutZones[]
```

### 6.3 Critical engines (build order)

1. **Vector kernel** — offset, boolean, join, node edit  
2. **Job/document** — sheets, undo  
3. **Profile toolpath + pocket + preview** — first real cut loop  
4. **Post runner** — GRBL-first  
5. **Machine streamer** — ShopPilot Control  
6. **V-Carve** — sign-making market  
7. **Heightfield composite + 3D rough/finish**  
8. **Nesting, double-sided, rotary**  
9. **Specialty strategies + laser**  
10. **Post Studio**  

### 6.4 Quality gates

- Golden G-code fixtures per strategy (checksum paths within tolerance).  
- Preview vs exported path consistency tests.  
- “Dirty toolpath” never silent-export without recalc prompt.  
- Safety: no machine run without explicit arm + hold chrome.

---

## 7. Team structure & ownership

| Squad | Owns | Headcount (indicative) |
| --- | --- | --- |
| **Platform** | App shell, document, undo, settings, packing | 2 eng |
| **Design 2D** | Vector tools, layers, import/export, text | 2 eng |
| **Model 3D** | Components, sculpt, import, composite Metal | 2 eng + 1 graphics |
| **Toolpaths** | Strategies, sim, templates, tiling | 3 eng (hardest) |
| **Posts & Tools** | Tool DB, materials, post language | 1–2 eng |
| **Machine** | Serial, jog, stream, keep-outs live | 1–2 eng (ShopPilot Control) |
| **Design/UX** | Stage rail, recipes, iconography, coach | 1 designer |
| **QA** | Golden jobs, hardware lab, regression | 1–2 |
| **PM / Docs** | Parity matrix, tutorials, shop recipes | 1 |
| **Hermes / agents** | Scaffold, tests, UI glue, fixtures | Parallel automation |

### RACI snapshot

- **PM** = parity acceptance against this matrix  
- **UX** = nothing ships without progressive-disclosure review  
- **Toolpaths lead** = technical authority on strategy math  
- **Machine lead** = safety authority on live cuts  

---

## 8. Phased roadmap (execution)

### Phase A — Foundation (Weeks 0–8)  
**Outcome:** Open job, draw rect, profile cut, preview, post GRBL, run on simulator/machine.

- App shell + Stage rail  
- Job setup single-sided  
- Core vector create/edit + layers  
- Profile + pocket + drill  
- Material setup + tool DB (minimal)  
- Preview simulation  
- GRBL post + Machine stage (from ShopPilot Control)  
- Command palette skeleton  

**Exit criteria:** reference calibration-pattern equivalent cut on real router.

### Phase B — Sign shop (Weeks 8–16)  
**Outcome:** Compete for 80% of hobby sign work.

- Text + text on curve + engraving fonts  
- Offset, boolean, fillets, nest (basic)  
- V-Carve + quick engrave  
- Trace bitmap  
- Tabs, ramps, leads  
- Job sheet PDF  
- Templates  

### Phase C — 3D relief (Weeks 16–28)  
**Outcome:** the reference’s artistic heart.

- Component tree + combine modes  
- Shape tools (angled/round/smooth/flat/custom)  
- Bitmap-to-component, emboss, smooth  
- 3D rough + finish  
- STL import/export  
- Sculpt mode v1  

### Phase D — Production & dual-side (Weeks 28–36)

- Multi-sheet, double-sided registration  
- Nest advanced, array TP, merge TP  
- Keep-outs full  
- Inlay + V-carve inlay recipes  
- Tiling  

### Phase E — Rotary & laser (Weeks 36–48)

- Rotary job + wrap + spiral  
- Rotary 3D modelling path  
- Laser cut/fill/picture  
- Drag knife / keyhole / rounding gadgets  

### Phase F — Power user (Weeks 48–60)

- Post Studio (reference post editing parity)  
- Photo V-Carve, sketch carving, fluting, prism, texture, moulding, thread  
- Document variables, remote tool DB optional  
- Polish, performance, App Store/notarization  

---

## 9. Team task board (epic IDs for Hermes + humans)

Use with `HERMES_BUILD_TODO.md` (Control) and new `HERMES_STUDIO_TODO.md` (below).

| Epic | Title | Phase |
| --- | --- | --- |
| STU-PLAT | Platform shell, stages, document | A |
| STU-VEC | Vector kernel + 2D tools | A–B |
| STU-TP-CORE | Profile, pocket, drill, preview | A |
| STU-POST | Post engine GRBL + library | A |
| STU-MACH | Machine stage integration | A |
| STU-TXT | Text & fonts | B |
| STU-VCARVE | V-Carve family | B |
| STU-COMP | Component composite system | C |
| STU-3DTP | 3D rough/finish | C |
| STU-NEST | Nesting & production | D |
| STU-2SIDE | Double-sided | D |
| STU-ROT | Rotary | E |
| STU-LASER | Laser pack | E |
| STU-SPEC | Specialty strategies | F |
| STU-POSTED | Post Studio | F |
| STU-UX | Recipes, coach, palette polish | continuous |

---

## 10. Competitive positioning (honest)

| Product | Strength | Our angle |
| --- | --- | --- |
| **Incumbent** | Deep creative toolpaths, ecosystem, tutorials | Mac-native, cleaner UI, integrated machine, modern Metal |
| **Fusion** | Full CAD/CAM parametric | Faster artistic/relief, shop-simple, not enterprise bloat |
| **Carbide Create** | Easy | Full reference-depth when needed |
| **V-carve** | Mid-tier incumbent | We target reference-depth with V-carve simplicity at surface |
| **LightBurn** | Laser UX gold standard | Learn from LB clarity for laser pack |

---

## 11. Legal / IP note for the team

- **Do not** copy third-party assets, clipart, icons, docs text, or proprietary file format internals.  
- **Do** implement **independent** geometry and toolpath algorithms to match *capabilities* and *user outcomes*.  
- Study is for **feature completeness and workflow research** only.  
- Prefer open standards (SVG, DXF, STL, 3MF) for interchange.

---

## 12. Success metrics

| Metric | Target |
| --- | --- |
| Time to first good cut (new user) | < 45 minutes (match the reference guide claim) |
| Tools visible at idle Design stage | ≤ 12 primary icons |
| All reference strategies reachable | ≤ 2 clicks or ⌘K |
| Preview vs machine surprise rate | Near-zero for software issues |
| Mac App polish (HIG) | Pass internal review |
| Parity matrix coverage | 100% listed features shipped or explicitly deferred with date |

---

## 13. Immediate next steps (this week)

1. Freeze product name: **ShopPilot** (app) / **Studio** stages for CAM.  
2. Publish **Feature Parity Spreadsheet** (export from §4) into project tracker.  
3. UX: one Figma/sketch of Stage Rail + Profile inspector (essentials vs advanced).  
4. Engineering: spin **vector kernel spike** (offset + boolean) and **Metal heightfield spike**.  
5. Hermes: continue Control path (machine) in parallel with Studio foundation todos.  
6. Hardware lab: one GRBL router + calibration plate SOP (from the reference guide §05).  

---

## 14. Document index

| Doc | Purpose |
| --- | --- |
| This file | Vision, full inventory, UX doctrine, roadmap |
| [`FEATURE_PARITY_MATRIX.md`](./FEATURE_PARITY_MATRIX.md) | Checklist form for tracking |
| [`UX_STAGE_SYSTEM.md`](./UX_STAGE_SYSTEM.md) | Detailed IA rules |
| [`../../HERMES_STUDIO_TODO.md`](../../HERMES_STUDIO_TODO.md) | Agent build list for Studio |
| [`../../HERMES_BUILD_TODO.md`](../../HERMES_BUILD_TODO.md) | Machine control list |
| [`../../AGENTS.md`](../../AGENTS.md) | Agent operating manual |

---

*The reference taught the industry how CNC creative software should think. ShopPilot’s job is to make that power feel inevitable on a Mac — never heavy, never incomplete.*
