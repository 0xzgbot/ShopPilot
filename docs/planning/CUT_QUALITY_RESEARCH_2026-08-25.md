# Cut quality research — V-carve / 3D / photo (2026-08-25)

> **Priority override:** this file is the product bar for toolpath *looks*.
> First-hour UX, T-bones, copy-along, and welcome-gallery wait.
> Do **not** reopen SPK-2010 medial-axis as a rewrite; remaining MA work is a
> named quality child below, not a reopen of PHASE W.
> Never stamp SPK-0623. Never pick SPK-1900g.

**Companion canvas:** open
[`cut-quality-bar.canvas.tsx`](/Users/zgbot/.cursor/projects/Users-zgbot-Desktop-ShopPilot/canvases/cut-quality-bar.canvas.tsx)
beside chat.

**Hermes paste:** [`CUT_QUALITY_HERMES_ORCHESTRATOR_PROMPT.md`](./CUT_QUALITY_HERMES_ORCHESTRATOR_PROMPT.md)

---

## Thesis (read this first)

Nobody gets “perfect results every time.” Vectric, Fusion, Carveco, and PhotoVCarve
sell a **closed quality loop**, not magic:

1. **The CAM knows the physical cutter** (V included angle + flat tip Ø; ball
   radius). Tool *center* is not the surface.
2. **Strategy matches surface class** (valley spine vs flats; steep walls vs
   shallow fields; photo grooves vs 3D height).
3. **A bigger tool hog, a smaller tool rest-machines.** Finish bits never bury.
4. **Preview shows leftover scallop / uncut cusps**, not a marketing render.
5. **The machine loop is assumed:** sharp bit, Z0 on a flat spoilboard, chip load
   in range, same V-bit for pocket and plug.

ShopPilot already has more *named* strategies than VCarve Desktop. The loss is
in (1) and (2). Verified in source 2026-08-25:

- `HeightfieldFinishEngine` drives **XY of the ball center along the heightfield
  Z**. Comment: “Finish: Nmm ball nose.” There is **no drop-cutter / normal
  offset**. Default `stepOverMm = 0.8` on a 3.175 mm bit = **25% of D**.
  Aspire’s documented finish stepover is **8–12% of D**.
- `PhotoVCarveToolpathEngine` rasters `Z = f(luminance)` at default
  `stepOverMm = 0.5`. The file comment claims “walls sloped by the V-bit
  angle”; `vBitAngleDegrees` is written into a G-code comment and never used
  in Z. Vectric PhotoVCarve’s product claim is grooves that vary in **width
  and depth**. We vary depth only.
- Lean scope still lists “photo V-carve” as a *new SKU* non-goal. The engine
  already exists (SPK-0901). This queue hardens **that** engine; it does not
  add a LightBurn-class photo product.
- `VCarveGeometry.depthForHalfWidth` is a **sharp-point V**. Real bits have a
  flat tip. Tip Ø exists on **inlay only** (`InlayPocketParams.tipDiameterMm`).
- 3D rough already has `stockAllowanceMm` (default 0.5) and
  `previousToolDiameterMm` rest. Finish does not consume that loop honestly
  (no ball compensation, no scallop-height gate).
- Lithophane **heightfield** already has invert / gamma / base thickness
  (`LithophaneEngine`). The *cut* still goes through the same finish raster.

---

## What incumbents actually do (mechanism, not brochure)

### V-carve (Vectric is the bar)

| Mechanism | Aspire / VCarve | ShopPilot today |
| --- | --- | --- |
| Depth from **local width**, not page Y | Yes — V-carve/engraving | **Yes** after SPK-2010 (`VCarveGeometry` + medial spine) |
| Continuous medial axis | Voronoi / exact-ish | **Grid MA** — honest leftover from 2010 close |
| Flat depth + clearance endmill | Yes; later tools rest the leftovers | Clearance pass + optional flat-area sweep (2010c) |
| V-bit **flat tip Ø** | Tool DB | **Inlay only** (2021a). General V-carve = sharp point |
| Inlay = same bit, glue gap, walls seat not floor | Dedicated inlay form; VWC recipes ~0.11″ pocket flat / 0.09″ plug start | Physics landed 2021a (tip / glue 0.05 pocket-out / fudge 1.002) |
| Rim chip protection | Shop practice: **V-bit first**, then floor clearance | Clearance-before-V is the lean default (opposite order for inlays) |
| Vector hygiene | Join/close/doctor — Fusion’s wound | 2020a0/a shipped |

MillMage 0.9: V-carve + linked clearance still “coming soon” in 2026 notes.
Carbide: inlay folklore on the forum; Advanced V-carve + rest not one loop.
Fusion: photoreal wins mockups; operators bounce to Vectric for signs because
vector CAM + V-geometry is faster than parametric history.

**“Perfect inlay” is geometry + shop, not software:** same included angle both
sides; plug seats on the **taper**; glue gap on the floor; humidity matched;
V-first if the pocket rim chips. CAM that omits tip Ø will look 0.1 mm wrong
on every letter.

### 3D relief (Aspire + Fusion split the market)

**Aspire 3D Rough** ([docs](https://docs.vectric.com/docs/V12.5/Aspire/ENU/Help/form/Rough%20Machining%20Toolpath/index.html)):

- **Z-level** (2D pockets at descending Z, optional profile first/last) for
  deep parts.
- **3D raster** for shallow parts (more even stock for finish, slower).
- **Boundary offset** so a raised object’s *edge* actually gets cut (tool
  center at the boundary otherwise leaves a wall).
- **Rest** = tool list; each tool only what the previous could not reach.

**Aspire 3D Finish** ([docs](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/Finish%20Machining%20Toolpath/index.html)):

- Ball (or tapered ball). **Stepover 8–12% of D** is the written default
  quality band.
- Fill: **Offset** (constant stepover along surface, climb/conventional) or
  **Raster** (lace, 0–90°).
- Offset retract lift between contours to kill perpendicular witness marks.
- Rest + boundary offset again.

**Fusion Manufacture** (not a sign shop, but the 3D *finish* bar):

- Rough: **Adaptive** = cap radial engagement (same idea as trochoid, 3D).
- Finish: **Scallop** = constant 3D stepover; **Parallel** for shallow;
  **Contour / constant-Z** for steep. Slope confinement splits the part.
- Rest machining on the finish op.
- Stock-to-leave on rough, finish takes the remainder.

**Carveco** (relief specialist, Maker+ vs Aspire 3D tools): raster, offset
raster, constant-Z, 3D offset, Z-level rough, **3D rest**. More 3D *strategy
nouns* than VCarve Desktop; Aspire still wins shop-floor preview trust.

**MeshCAM / cheap raster CAM:** tool center follows Z — same class as
ShopPilot finish today. That is why those cuts look “3D printed in wood”
(cusps, overcut valleys, leftover peaks).

ShopPilot 3D rough (`HeightfieldRoughEngine`): z-level X-runs, stock
allowance, optional rest via `previousToolDiameterMm`, inverse mill. That is
the *right family*. Finish is MeshCAM-class.

### Photo / lithophane (PhotoVCarve is the bar)

Vectric PhotoVCarve product copy: lines of grooves that vary in **width and
depth**. Ball-nose lithophanes: **8–15% line spacing**, **45°** raster to
cut load, invert light/dark, **rough ~50% then finish ~10%**, leftover
~1–1.5 mm Corian, **spoilboard must be flat** or the thin plate punches
through. Smaller ball = more detail = longer time.

ShopPilot:

- `LithophaneEngine` already does invert / gamma / base thickness / modes.
- `PhotoVCarveToolpathEngine` is a **Y-raster of Z(luminance)** with a V-bit
  *comment*, not a V-groove width model.
- Photo and 3D finish fail in **different** ways. 3D: no ball radius
  (point cutter). Photo: V-angle unused, so no groove **width** — not a
  missing ball radius.

---

## Quality math we can assert in CLTs

**Ball finish (drop-cutter, 2.5D heightfield):** for a ball of radius `R`,
the tool center sits `R` above the contact point along the local normal. On a
flat, center Z = surface + R (or stock-top convention equivalent). On a
slope, the center is offset in XY as well. Tracing `z = surface` with the
center **overcuts concave valleys by ~R** and **leaves cusps on convex
peaks**. That is visible on any dome fixture.

**Scallop height** (lace, stepover `s`, ball `R`, shallow):
`h ≈ s² / (8R)` for small s. Aspire’s 10% of 3.175 mm → s ≈ 0.32 mm,
`h ≈ 0.008 mm` (8 µm). Our default s = 0.8 mm → `h ≈ 0.050 mm` (50 µm)
(**~6× more leftover** before even counting missing radius compensation).

**V-bit tip:** depth for half-width `w` with included angle `A` and tip Ø `t`:
`z = −(w − t/2) / tan(A/2)` for `w > t/2`, else floor. Sharp-point
(`t = 0`) is what `VCarveGeometry` does now.

**Photo V-groove width** at depth `d`: `width = t + 2 d tan(A/2)`. Stepover
must be ≤ that width or you leave uncut ridges between “photo lines.”

---

## Quality-first card queue (Mac)

Parent **SPK-2100** — Cut quality bar (V / 3D / photo). DoD on parent:
Engine + UI + Persist + Verify per child. File on `MASTER_KANBAN.md` before
claiming. Win mirrors H-7xx same wave.

Gate every child: `./scripts/verify_locked.sh ShopPilotVerify2100x`.
Never `swift test`. All Swift via lock. `--max-runtime 60m` (90m for 2100a).

### Wave Q1 — 3D finish (highest visual delta)

**SPK-2100a** **CAM** Drop-cutter / ball compensation on `HeightfieldFinishEngine`
- Tool center offset by ball radius. Default **init** `stepOverMm = 0.10 * toolDiameterMm`.
  Decode missing key still 0.8 (legacy).
- CLT: dome fixture — compensated Z is **not** the surface Z; valley not
  overcut by ~R.
- **No Finish 3D form today** (Rough 3D has `Rough3DParamsForm` +
  `applyRough3DParams`; finish has neither). Engine+CLT only on this card.
- Out: inspector UI (2100b), Fusion scallop, steep/shallow split, pencil.
- Files: `HeightfieldToolpath.swift` finish engine + `HeightfieldFinishParams`.
- Verify: `ShopPilotVerify2100a`.

**SPK-2100b** **CAM+UI** Create Finish 3D form + raster angle 0 / 45 / 90
- Deps: 2100a. NEW form (mirror Rough 3D) + `applyFinish3DParams` + Cut
  inspector branch. Stepover as % of D + scallop readout. Default angle 0.
- Out: Offset-along-surface (later).
- Verify: `ShopPilotVerify2100b` — 45° visits cells the 0° pass misses on a
  diagonal ridge + app build.

**SPK-2100c** **PREV** Scallop-height leftover in Preview
- Heightfield sim (or wire overlay) colors leftover `h ≈ s²/(8R)` vs a
  0.02 mm “shop quality” band. Honest, not photoreal.
- Out: Fusion-style shaded metal.
- Verify: python or CLT that the formula is shown and updates when stepover
  changes.

**SPK-2100d** **CAM** Rest finish from previous tool
- Deps: 2100a. `previousToolDiameterMm` (0 = compensated finish, no rest).
  Smaller ball only leftover cusps the previous ball could not reach.
- Out: Fusion pencil / collapsed pencil.
- Verify: `ShopPilotVerify2100d`.

### Wave Q2 — photo / lithophane (V-angle unused, not missing ball radius)

**SPK-2110a** **CAM** PhotoVCarve = V-groove width+depth
- Depth from luminance (keep). **Width from V angle + tip + depth.** Stepover
  default `0.12 * grooveWidth` or 10% of D if ball mode.
- Raster angle default **45°**. Invert already lives on lithophane params —
  expose on Photo V-Carve form.
- Out: cross-hatch (optional later).
- Verify: `ShopPilotVerify2110a` — at depth D, adjacent lines overlap by
  construction (no uncut ridge wider than tip).

**SPK-2110b** **CAM** Photo/litho two-pass (rough 50% / finish 10%)
- Linked ops or one form with two tools. Finish stepover 8–12%.
- Lithophane leftover thickness warning if `stock − maxDepth < minThickness`.
- Verify: `ShopPilotVerify2110b`.

### Wave Q3 — V-carve remaining honesty

**SPK-2120a** **CAM** V-bit tip Ø on `VCarveGeometry` / `VCarveParams`
- Same number as inlay default 0.1 mm. `tip=0` = today’s sharp-point
  (byte-stable goldens).
- Verify: `ShopPilotVerify2120a` — wide valley depth changes when tip > 0;
  tip=0 matches current goldens.

**SPK-2120b** **CAM** Inlay rim order: V-bit walls then floor clearance
- Optional toggle, default **V-first** on inlay (shop practice). Existing
  clearance-before-V stays the default for ordinary V-carve.
- Verify: `ShopPilotVerify2120b` — first cut moves are V (G1 Z valley), then
  endmill floor.

**SPK-2120c** **GEO** Finer medial-axis cell (not a new algorithm)
- Expose `medialAxisCellMm` already on the Valley form; add a “crisp letters”
  preset 0.2 mm with a time warning. Do **not** rewrite `MedialAxis.swift`.
- Verify: existing 2010a CLT + one letter fixture at two cell sizes.

### Explicitly later (not this quality wave)

Fusion Adaptive 3D · steep/shallow split · pencil/collapsed pencil · Aspire
Offset finish with retract · exact Voronoi MA · 2022f resume · copy-along
(2023e) · App Store. (Welcome gallery and T-bones already `[x]` on PHASE X.)

---

## Win mirrors (file when Mac twin `[x]`)

| Mac | Win |
| --- | --- |
| 2100a | H-701 drop-cutter finish |
| 2100b | H-702 raster angle |
| 2110a | H-703 PhotoVCarve width+depth |
| 2120a | H-704 V-bit tip on general V-carve |

H-610 trochoid stays on the family-contract board; it is not this quality wave.

---

## How to run this (board as of 2026-08-25 night)

PHASE X first-hour/joinery is done except parked **2022f** and optional **2023e**.
1. Do **not** spawn a Nous fan-out (429s). One Mac coder.
2. Dispatch **2100a** (engine only). Then **2100b** (create the missing Finish 3D form).
3. **2110a** is parallel-ok vs 2100a (PhotoVCarve files, not HeightfieldToolpath).
   Still serialize if the free-model RPM bucket is hot.
4. Win idle until 2100a `[x]`, then file H-701.

---

## Sources

- Vectric Aspire V12/V12.5: 3D Rough, 3D Finish, VCarve Inlay, PhotoVCarve product + case study
- Autodesk Fusion: Adaptive Clearing, Scallop Finishing, HSM tutorial (steep contour / shallow scallop / rest)
- IDC Woodcraft / VWC inlay depth recipes; RoboCNC PhotoVCarve + Corian lithophane
- ShopPilot: `HeightfieldToolpath.swift`, `PhotoVCarveToolpath.swift`, `VCarveGeometry.swift`, `InlayToolpath.swift`, `LithophaneEngine.swift` (read 2026-08-25)
- Prior family review canvas 2026-08-24; [`research/MARKET_GAPS_2026.md`](./research/MARKET_GAPS_2026.md)
