# Agent prompt — SPK-2010 V-Carve quality (the incumbent gap)

Paste this whole file into Hermes/Cursor as the job. North star: `AGENTS.md` + `docs/planning/LEAN_CNC_SCOPE.md`. Board: `MASTER_KANBAN.md` only.

**This is the P0 quality gap from the 2026-08-24 family review.** the V-carve pro tier still wins letters because depth follows **local channel width along the valley spine**. ShopPilot currently traces the **outline** and fakes depth with **Y-position shading**. That is not V-carve.

---

## What is broken (read this before writing code)

`Sources/ShopPilotCore/VCarveEngine.swift` today:

1. Walks each input polyline (the **wall**, not the valley).
2. Sets Z from the point’s **Y** in the vector bbox (“higher Y → shallower”). A letter moved on the sheet carves differently. A wide bulb and a narrow neck at the same Y get the same depth.
3. Multi-pass is `ceil(tipWidth / stepOver)` copies of that outline. The **interior is never visited**.
4. `SPK-VCarveClear` rasters **around** letters with an end mill. It does not make the V-bit follow a medial axis. Keep it. Do not confuse it with this work.

The incumbent (and VectorPilot, our Windows sibling) do this instead:

> At each point on the **medial axis** (skeleton / valley), half-width `w` = distance to the nearest boundary. For included angle `A`, `z = -(w / tan(A/2))`, clamped to max depth. Wide regions go deep; necks stay shallow. The bit rides the spine, not the outline.

**Sibling (read-only):** `~/Desktop/VectorPilot`

| File | What to copy (semantics, not C#) |
| --- | --- |
| `src/VectorPilot.Engine/MedialAxis.cs` | Discrete clearance field → ridge cells → chained polylines |
| `src/VectorPilot.Engine/VCarveGeometry.cs` | `DepthForHalfWidth`, `DistanceToNearestOtherEdge` |
| `src/VectorPilot.Engine/Toolpaths/VCarveEngine.cs` | Width-derived Z on outline; medial pass; optional flat-area sweep (P-202) |
| `tests/VectorPilot.Tests/VCarveMedialAxisTests.cs` | Dumbbell AC — **port these asserts into the Mac CLT** |

**Do not edit VectorPilot.** Independent Swift. No the proprietary CRV format. No proprietary ports.

---

## Product rules (non-negotiable)

- Offline Mac app. GRBL-class G-code. No cloud. No auto-start stream.
- All Swift via `./scripts/swift_locked.sh`. Never `rm -rf .build`. Worktree-only `Sources` edits.
- One Swift compile at a time. If lock waits, heartbeat and wait.
- DoD per card: Engine + UI + Persist + Verify as specified. Never `[x]` for file-drop/build-only.
- Claim: `[ ]` → `[~]` + work log, then `[x]` + work log. Parent stays `[~]` until children `[x]`.
- Assignee: `coder`. Max runtime **60m** per child. Parent `SPK-2010`.
- Do **not** stamp `SPK-0623`. Do **not** choose license `SPK-1900g`.

---

## Geometry contract

### Depth (must)

```
halfAngle = vBitAngleDegrees/2 * π/180
z = -min(halfWidth / tan(halfAngle), maxDepth)
```

`halfWidth` is clearance to the nearest **other** edge (skip the two segments that touch this vertex). Never derive Z from page Y.

### Medial axis (must, closed paths only)

Raster a clearance field inside the closed outline (cell size `medialAxisCellMm`, default 1.0 mm). Cap grid at **4_000_000** cells by coarsening `cell` (same guard as VectorPilot). Ridge = local max of clearance along X **or** Y **or** either diagonal (requiring both axes drops the spine of a long channel). Chain 8-connected ridge cells, longest path first. Depth at each ridge point = `DepthForHalfWidth(clearance, angle, maxDepth)`.

Open polylines: **no** medial pass (no interior). They still carve with width-derived Z along the path.

### Flat-area clearing (2010c, optional flag default **off**)

Where ridge clearance > `(tipWidthAtMaxDepth / 2) * flatAreaThresholdFactor` (default 1.5), the V-bit bottoms out and leaves stock beside the spine. Sweep those runs laterally at `-maxDepth` with `flatAreaStepOverMm` (default 1.0), both sides of the spine, staying inside the extra half-width. Marker comment: `(Flat area clearing: …)`.

### Keep

- Header `%`, optional `M3 S` if rpm > 0, existing `O=VCARVE_CLEARANCE` **before** `O=V_CARVE_TOOLPATH` when clearance is on.
- `O=V_CARVE_TOOLPATH`, `(V-Bit: N°)`, M30, trailing `%`.
- Lead-in/out, safe Z 5.0 between passes, no M6, no G28.
- Outline multi-pass by step-over **stays** in v1 (VectorPilot kept it). Only Z semantics + skeleton change.
- `ShopPilotVerifyVCarveClear` must remain PASS.

### Explicitly out of this parent

Exact continuous Voronoi medial axis; inlay tip/glue-gap physics; Photo V-Carve; pocket rest; T-bones; laser; posts; preview Metal; VectorPilot edits; “looks like the incumbent in a photo” (no hardware). Quality bar = **dumbbell + circle + slot CLTs**, not the incumbent suite pixel match.

---

## Params (additive, legacy-safe)

Extend `VCarveParams` (existing Codable with `decodeIfPresent`). Missing keys → defaults. Old jobs load.

| Field | Default | Meaning |
| --- | --- | --- |
| `medialAxisPass` | `true` | Skeleton pass on closed vectors |
| `medialAxisCellMm` | `1.0` | Grid resolution (mm) |
| `flatAreaClearing` | `false` | Lateral sweep of too-wide ridge |
| `flatAreaThresholdFactor` | `1.5` | × tip-half-width |
| `flatAreaStepOverMm` | `1.0` | Sweep spacing (mm) |

Default **on** for medial: new and recalc’d V-carve must visit interiors. Outline-only remains available by setting the flag false (CLT must prove the dumbbell interior is empty without it).

---

## Files / hot spots

**Wave A (new files only, parallel-ok):**

- `Sources/ShopPilotCore/VCarveGeometry.swift` — NEW
- `Sources/ShopPilotCore/MedialAxis.swift` — NEW
- `Sources/ShopPilotVerify2010a/main.swift` — NEW
- `Package.swift` — register `ShopPilotVerify2010a` **before** or **with** this card (1900a pattern)

**Wave B (serial — `VCarveEngine.swift` lock):**

- `Sources/ShopPilotCore/VCarveEngine.swift` — replace Y-shading with `VCarveGeometry`; emit medial pass; later flat-area
- `Sources/ShopPilotVerify2010b/main.swift` — dumbbell engine CLT
- `Tests/ShopPilotTests/VCarveEngineTests.swift` — only if a CLT-adjacent XCTest asserts Y-shading; do **not** spend the card on XCTest (CLT machine has no XCTest)

**Wave C (serial — form + params):**

- `VCarveParams` Codable keys
- `Sources/ShopPilot/ContentView.swift` — `VCarveParamsForm` (~line 2093): GroupBox **Valley** with medial toggle, cell mm, flat-area toggle + threshold/step
- Recalc already uses `vcarveParams()` — no new strategy kind

Do **not** touch `PhotoVCarveToolpath.swift`, serial/streamer, or VectorPilot.

---

## Split cards (mandatory — do not implement as one epic)

Already filed on `MASTER_KANBAN.md` under **PHASE W**. Run **one card at a time**. Start at **2010a**.

### Parent — SPK-2010 **CAM** V-Carve quality vs the incumbent

- DoD: Engine (width-Z + medial + optional flat) + UI (Valley group on V-Carve form) + Persist (additive JSON) + Verify (2010a/b/c CLTs + VCarveClear regression).
- Out of scope: inlay physics, Photo V-Carve, exact Voronoi, live wood.

### SPK-2010a **CAM** MedialAxis + VCarveGeometry + CLT — NEW FILES ONLY — 60m — parallel-ok

**AC:**

1. `MedialAxis.compute` on a 40 mm-radius circle (72 segs, cell 1.0) → non-empty; `maxClearanceMm` within **3 mm** of 40.
2. 200×20 mm rectangle slot → longest ridge spans X much more than Y (`width > height * 3`).
3. `VCarveGeometry.depthForHalfWidth(10, angle: 90, maxDepth: 50)` ≈ **-10** (90° bit: half-angle 45°, tan=1). Same half-width at 30° is deeper (more negative) than at 90°, and clamped to `-maxDepth` when width is huge.
4. Degenerate outline (<3 points) → empty skeleton. Every ridge point of the dumbbell fixture is inside the polygon.

**Out of scope:** `VCarveEngine.swift`, SwiftUI, Package UI besides registering this CLT.

**Verify:** `./scripts/verify_locked.sh ShopPilotVerify2010a`  
Then `./scripts/swift_locked.sh build --target ShopPilotCore` only if needed.

Pre-register `ShopPilotVerify2010a` in `Package.swift` + placeholder dir **before** a second agent touches Package.swift.

Print `ShopPilotVerify2010a: PASS — medial axis + V-carve depth geometry` on success.

### SPK-2010b **CAM** Wire width-Z + medial pass into VCarveEngine — serial — 60m — deps: 2010a

**AC:**

1. Outline Z uses `VCarveGeometry` (not Y-shading). A 12 mm-wide slot and a 40 mm circle at the same sheet Y do **not** share one Z; the circle’s deepest cut is deeper.
2. Closed dumbbell (port VectorPilot fixture: bulbs r=30 at x=40 and x=160, neck half-width 6, cy=100): with `medialAxisPass=true`, G1 cuts exist near neck centerline (`|y-100|<3`, x in 75…125) **and** inside the left bulb (distance to (40,100) < 12). Deepest bulb Z is more negative than deepest neck Z.
3. `medialAxisPass=false` → left-bulb interior (dist to centre < 12) has **no** cut at Z<−0.01. Medial on → more G1 XY cuts than medial off.
4. Open polyline still emits `O=V_CARVE_TOOLPATH` and has **no** `(Medial axis:` comment.
5. `ShopPilotVerifyVCarveClear` still PASS. No M6/G28. M3 only if rpm>0. Deterministic: two computes, identical `[String]`.

**Out of scope:** flat-area sweep, form UI, Photo V-Carve.

**Verify:** `./scripts/verify_locked.sh ShopPilotVerify2010b` and `./scripts/verify_locked.sh ShopPilotVerifyVCarveClear`

Print `ShopPilotVerify2010b: PASS — V-carve valley spine` on success.

### SPK-2010c **CAM** Flat-area clearing + params persist — serial — 60m — deps: 2010b

**AC:**

1. Closed 80×40 mm rect, 90° bit, `maxDepthOfCutMm=2` (reachable tip width 4 mm), `flatAreaClearing=true` → G-code contains `(Flat area clearing:` and extra G1 at Z≈−2 offset from the spine. Same job with flag false → no that comment.
2. Additive Codable: `{}` / pre-2010 JSON decodes `medialAxisPass==true`, `flatAreaClearing==false`. Round-trip keeps all five new fields.
3. Recalc with stored `paramsJSON` (mutate `flatAreaClearing`, recalc) changes G-code.

**Out of scope:** new strategy in the Add menu (still V-Carve).

**Verify:** `./scripts/verify_locked.sh ShopPilotVerify2010c`

### SPK-2010d **UX** Valley group on V-Carve form — serial — 45m — deps: 2010c

**AC:**

1. Cut inspector V-Carve form shows GroupBox **Valley** (or equal): Medial axis toggle, cell mm, Flat area toggle, threshold, step-over. Apply → `applyVCarveParams` regenerates.
2. Accessibility: toggles have labels. Python gate greps `medialAxisPass`, `Valley`, `MedialAxis`.
3. Beginner mode: Valley group still visible (this is the default V-carve, not a pro-only gadget).

**Out of scope:** inlay wizard, feeds library.

**Verify:** `python3 scripts/verify_2010d_vcarve_quality.py` PASS + `./scripts/swift_locked.sh build --target ShopPilot`

### SPK-2010e **QA** Sign-recipe regression — serial — 45m — deps: 2010b

**AC:**

1. `ShopPilotVerify1106a` and `ShopPilotVerify1106b` PASS (sign recipe still materializes a V-Carve node with cut moves). If goldens asserted exact line counts against Y-shading, update them to **presence + valley invariants**, not byte-identical old G-code.
2. `ShopPilotVerify1136d` PASS (form-field round-trip still includes §O keys plus new Valley keys).
3. Work log notes: default medial-on **changes** closed-shape G-code vs 2010-era jobs; dirty+recalc is required (existing safety model).

**Out of scope:** photographing a board; SPK-0623.

**Verify:** `./scripts/verify_locked.sh ShopPilotVerify1106a` + `1106b` + `1136d` + `VCarveClear`

---

## Dumbbell fixture (copy into 2010a/b CLTs)

Match VectorPilot `VCarveMedialAxisTests.Dumbbell()`:

- Left bulb centre `(40, 100)`, right `(160, 100)`, radius 30, neck half-width 6.
- Closed polyline. Cell 1.5 mm for engine tests (faster).

Do **not** invent a different dumbbell and then weaken asserts.

---

## Safety / G-code hygiene

- Cut moves: G0 to Z5.0 before XY rapids between valley segments.
- Units mm. `%.3f` words.
- Never stream on generate.
- Keep-out: if current V-carve ignores keep-outs, document follow-up — do not silently mill a keep-out if Profile already respects them and the reuse is ≤20 lines; else leave a `// follow-up` comment.

---

## Definition of done (parent)

- [ ] 2010a CLT PASS
- [ ] 2010b CLT PASS + VCarveClear regression
- [ ] 2010c CLT PASS
- [ ] 2010d form + python gate
- [ ] 2010e sign/§O regressions
- [ ] App target `swift_locked.sh build --target ShopPilot` (on 2010d or 2010e)
- [ ] Work logs on all cards
- [ ] No full `scripts/test.sh` required (ad-hoc slice verify OK; note it)

---

## Orchestrator note

Wave A: one agent, new files only. Wave B/C: serialize on `VCarveEngine.swift` / `ContentView.swift`.

If 2010a times out after files landed: verify CLT yourself; do not rewrite the skeleton.

Honest remaining gap after parent `[x]`: grid medial axis is still not the incumbent's exact continuous axis; letters will look close, not identical. Next quality card (not this parent) would be finer cell / exact MA. Do not sneak that into 2010.

---

## Hand-off block (copy below the line)

```
You are building ShopPilot at ~/Desktop/ShopPilot.
Read AGENTS.md safety + docs/planning/LEAN_CNC_SCOPE.md.
Implement SPK-2010 V-Carve quality per docs/planning/SPK-2010_VCARVE_QUALITY_AGENT_PROMPT.md
Claim the first Ready child (2010a if MedialAxis.swift is missing).
One card. Engine+Verify first. All swift via swift_locked.sh. Never rm -rf .build.
Do not edit VectorPilot. Do not add inlay physics, Photo V-Carve, or exact Voronoi.
Loop: claim → AC → [x] + work log → next child. Never idle on [!]. Never stamp SPK-0623.
```
