# Hermes mega-prompt — CAM first-hour UI (SPK-1800)

Copy everything below the line into one Hermes session. Outer wall-clock may be long; **implement internally as 45–90 minute slices**. Do **not** rubber-stamp SPK-0623. Laser/LightBurn is **held**. Simulator only — never live serial jobs.

Board: parent **SPK-1800** + **1800a–h** on `MASTER_KANBAN.md`. This prompt may run **after or in parallel with** SPK-1700 Preview playback (`docs/planning/PREVIEW_PLAYBACK_HERMES.md`).

---

```
You are a coding agent on ShopPilot at ~/Desktop/ShopPilot (personal-use Mac CNC — App Store/notarize are out of scope).

North star: docs/planning/LEAN_CNC_SCOPE.md
Board: MASTER_KANBAN.md
Safety: AGENTS.md §2 (Hold/Reset always visible when connected; no auto-start stream; simulator-first)
UI doctrine: 6-stage rail Setup → Design → Model → Cut → Preview → Machine; palettes + inspector; ≤12 icons per stage; no NavigationSplitView rewrite; no icon walls; Mac creative app (not a ribbon CAD clone); no rainbow chrome.
Prompt file: docs/planning/CAM_UI_FIRST_HOUR_HERMES.md

## Hard rules
- Claim cards `[ ]` → `[~]` then `[x]` + Work log. Never `[x]` without Engine + UI + Persist + Verify for that slice (Persist may be session/job JSON or UserDefaults as specified).
- Worktree-only Sources edits (git worktree under .worktrees/ or repo convention). Do not edit the user's dirty main tree if a worktree exists.
- ALL Swift: `./scripts/swift_locked.sh` or `./scripts/verify_locked.sh`. NEVER `rm -rf .build`. NEVER full-package `swift test`. CLT has no XCTest.
- One swift compile at a time (lock). Prefer `--max-runtime 45m` or `60m` per slice.
- Out of scope globally: laser/LightBurn product, Metal chip sim, Fusion-style 3D CAD, App Store, SPK-0623 `[x]`, live CNC / real serial job (SimulatorTransport only), merging Machine WCS into Design on one card.
- Parent SPK-1800 stays `[ ]` until 1800a–h are `[x]`. Do NOT mark SPK-0623 done.

## BUG-03 and SPK-1700 (read the board; do not invent status)

Check MASTER_KANBAN marks at session start:

- **SPK-UI-BUG-03** and **SPK-1700 / 1700a–d**: if still `[ ]`, that is OK for Phase R Design/Inspector/Machine work.
- **Do NOT block SPK-1800a (snap)** on BUG-03 or 1700. Snap does not need Cut generate or Preview raster.
- Prefer a *separate* Hermes for BUG-03 then 1700 (PREVIEW_PLAYBACK_HERMES.md) if you are also assigned Preview. If you are only on 1800, skip BUG-03 unless you have spare capacity *and* you will not stall 1800a.
- **SPK-1800h (orbit):** if 1700 still `[ ]` **or** 1700a not `[x]`, implement orbit **only on Model** (`ModelStageView` / `ReliefCanvasView`). **Do not edit `ToolpathPreviewView.swift`.** If 1700a already `[x]` and you need Preview orbit, wait until 1700a–c `[x]` or serialize that file with the 1700 owner.
- **SPK-1800f (tabs/leads):** draw on Design `toolpathOverlayLayer` while 1700 owns Preview. Do not collide on Preview.

## Concurrency (mandatory)

Serialize **DesignCanvasView.swift**: **1800a → 1800b → 1800c → 1800d** (then 1800f if it still edits that file).

After **1800a** `[x]`, these may run in parallel **if files stay distinct**:
- 1800e — `InspectorShell.swift` (not Cut forms in ContentView except read-only reuse)
- 1800g — `MachineConnection.swift`
- 1800h — `ModelStageView.swift` only (while 1700 open)

Do not start a second `swift` while waiting. `swift_locked.sh` serializes compiles.

## Do not break pan/zoom

Today (`DesignCanvasView.swift`):
- Pinch/`MagnificationGesture` multiplies `scale` (0.3…8). Keep it.
- Select empty-drag currently **pans** with a broken `translation * 0.02` increment — 1800b **replaces** empty-drag with marquee.
- **Chosen pan (document in toolbar hint + this prompt):** **Space+drag pans**. If the event is a middle-button drag, treat it like Space (same pan). Option/⌥ is **not** pan (leave Option for future modifiers). Update `CanvasCreateTool.select` hint: it currently says “drag empty space to pan” — that must become marquee + Space-to-pan.
- Model sculpt mode: drag is brush; non-sculpt drag pans. Orbit (1800h) must not steal sculpt strokes; use a modifier or a View/Orbit vs Sculpt mode. Document the pick in the toolbar.

## Ground truth (read before coding)

- `Sources/ShopPilot/DesignCanvasView.swift` — `gridLayer` already draws a world-anchored grid (step `20 * scale`) + amber (0,0) crosshair. `model(_:)` / `screen(_:_:)` map view ↔ sheet. Create tools write unsnapped points. `selectDragChanged` pans on miss. `toolpathOverlayLayer` strokes `WireframeRenderer` G-code (rapid blue / cut green) — no tabs/leads.
- `Sources/ShopPilot/InspectorShell.swift` — Cut inspector lists names + times, **not** F/S/Z. Selection badge for `.toolpath`.
- `Sources/ShopPilot/ContentView.swift` `CutStageView.selectedDetail` — Profile/Pocket/Drill/V-Carve **forms** (full params). 1800e must **not** duplicate those forms; Inspector gets a compact F/S/Z readout.
- `Sources/ShopPilotCore/ToolpathTree.swift` — `paramFeedRate`, `paramSpindleRpm`, `paramCutDepth` already exist. Use them (extend 3D nodes if nil and cheap).
- `Sources/ShopPilot/MachineConnection.swift` — `MachineConnectionView`; status line is a short string. Parsed pose lives on `controller.machineSession.mPosX/Y/Z` (`ShopPilotCore/MachineSession.swift` via `StatusParser`). No large DRO.
- `Sources/ShopPilot/ModelStageView.swift` — `ReliefCanvasView` is a 2.5D heightfield with pan/zoom, not orbit.

---

### 1) SPK-1800a — Grid snap
Parent: SPK-1800. **Ready even if BUG-03 and 1700 are `[ ]`.**

AC:
1. Snap toggle (Design toolbar and/or inspector), default on or off — persist on job/session (JSON or `@AppStorage` documented).
2. Create (rect/circle/line/polyline vertices) and Select-move commit **snap to the same grid** `gridLayer` uses (world step 20 in current canvas units unless you unify to sheet mm — then grid + snap share one step).
3. Pinch-zoom still works. Do not change marquee yet.

Out of scope: marquee, canvas DRO, origin picker, Preview, Machine WCS.

Verify: `python3 scripts/verify_1800a_snap.py` **or** `./scripts/verify_locked.sh ShopPilotVerify1800a` (register in Package.swift). Prove snap helper: e.g. 13 → 20, 27 → 20 or 40 depending on step; toggle off leaves 13. Optional grep that DesignCanvasView calls the helper on commit.

Slice ≤60m.

---

### 2) SPK-1800b — Marquee select
Parent: SPK-1800. Deps: 1800a. **Serialize DesignCanvasView.**

AC:
1. Select tool: drag on **empty** canvas draws a rubber-band rect; on mouse-up, shapes whose bounds intersect the marquee join `session.selectedShapeIndices` (⌘/⇧ adds; plain replaces).
2. Drag on a **hit** shape still moves (and still snaps if 1800a on).
3. **Pan = Space+drag** (and middle-button drag). Document in `CanvasCreateTool.hint` + toolbar help. Empty drag is **not** pan.

Out of scope: lasso; node-edit; origin; WCS.

Verify: python grep (marquee state, Space modifier / `NSEvent.pressedMouseButtons`, hint text no longer “empty space to pan”) and/or `ShopPilotVerify1800b` for rect-intersection helper.

Slice ≤60m. **Do not break MagnificationGesture.**

---

### 3) SPK-1800c — Cursor XY DRO (Design)
Parent: SPK-1800. Deps: 1800b.

AC:
1. Design canvas shows live **X / Y** (sheet mm, same as `model(_:)`) while hovering or dragging — overlay corner or toolbar, monospaced, accessibility label e.g. “Cursor X”.
2. Hover tracking is not polyline-only (`onContinuousHover` today returns early unless polyline).
3. Does not capture scroll/pinch.

Out of scope: Machine DRO (1800g); Z on 2D canvas.

Verify: `scripts/verify_1800c_dro.py` and/or `ShopPilotVerify1800c`.

Slice ≤45m.

---

### 4) SPK-1800d — Sheet origin (corner / center)
Parent: SPK-1800. Deps: 1800c. **Do not merge WCS into Design.**

AC:
1. Control (segmented or inspector): Design datum = sheet **corner** or **center**. Persist on job/sheet.
2. Grid, snap, canvas DRO, and the origin glyph use that datum. Center mode places the amber datum at sheet center, not only world (0,0) if that is the wrong corner.
3. **UI copy (one sentence):** Design origin is the sheet drawing datum. Machine work zero / `mPos` / G54 live on the Machine stage and are not changed by this control.

Out of scope: G54–G59 UI; jogging; StatusParser; Preview.

Verify: persist round-trip in CLT or python + model encode; UI strings mention Machine zero separately.

Slice ≤60m.

---

### 5) SPK-1800e — CAM inspector F/S/Z
Parent: SPK-1800. Parallel-ok after 1800a. File: **InspectorShell.swift**.

AC:
1. When selection is a toolpath/operation (`session.selection` / `selectedToolpathID` / tree node), Inspector shows **F** (mm/min), **S** (RPM), **Z** (cut depth mm) from `ToolpathTreeNode.paramFeedRate` / `paramSpindleRpm` / `paramCutDepth`.
2. Visible on Cut **and** when inspector is showing that selection from other stages if the same selection exists — minimum: Cut stage inspector.
3. Do **not** replace `ContentView` `selectedDetail` strategy forms; Inspector is a compact readout (PropertyRow). Empty/unknown → “—” not a crash.

Out of scope: new CAM engines; laser; rewriting ProfileParamsForm.

Verify: `scripts/verify_1800e_inspector.py` (InspectorShell mentions paramFeedRate or F/S/Z rows) and/or `ShopPilotVerify1800e`.

Slice ≤45m.

---

### 6) SPK-1800f — Tabs and leads on Design overlay
Parent: SPK-1800. Deps: 1800d if still on DesignCanvasView. **No ToolpathPreviewView while 1700 `[ ]`.**

AC:
1. When toolpath overlay is on, **tabs** and **lead-in/out** are drawn (distinct color/dash from rapid/cut) from profile params + generated path/G-code — not a new tab engine.
2. Overlay off still hides them with `.toolpaths`.

Out of scope: changing tab widths in the engine; 1700 heightfield; Preview playback.

Verify: `scripts/verify_1800f_tabs.py` and/or `ShopPilotVerify1800f` (helper emits ≥1 tab segment when `addTabs` and known geometry).

Slice ≤90m.

---

### 7) SPK-1800g — Machine DRO (mPos)
Parent: SPK-1800. Parallel-ok. File: **MachineConnection.swift**.

AC:
1. Large monospaced **X Y Z** from `controller.machineSession.mPosX/Y/Z` (parsed status, not a hardcoded 0,0,0 label).
2. Updates when simulator reports `<Idle|MPos:…>`. Optional smaller WPos — do not replace mPos.
3. Hold/Resume/Reset stay visible when connected. No auto-run on connect.

Out of scope: Design origin; live serial job; G54 editor.

Verify: `scripts/verify_1800g_machine_dro.py` (MachineConnectionView reads `mPosX` or `machineSession.mPos`) and/or CLT.

Slice ≤45m.

---

### 8) SPK-1800h — 3D relief orbit (thin 2.5D)
Parent: SPK-1800.

**Collision rule:** If SPK-1700 or 1700a is still `[ ]`, **only** `ModelStageView.swift` / `ReliefCanvasView`. Do not touch Preview. If 1700a is `[x]` and you want Preview orbit too, that is a **follow-up card** after 1700a–c — not this slice.

AC:
1. Model heightfield can **orbit/tilt** (SceneKit plane with height as displacement/texture **or** a 2.5D orbit: rotate yaw/pitch around the relief). Thin. Not Fusion, not mesh CAD, not Metal chips.
2. Sculpt mode: brush drag unchanged. Orbit via explicit Orbit tool **or** Option+drag — **pick one and document** in the Model toolbar.
3. Fit / Zoom +/− still work.

Out of scope: 1700 filled raster; playhead; bit stamp; true 3D CAM viewport.

Verify: `scripts/verify_1800h_orbit.py` and/or `ShopPilotVerify1800h`. Then `./scripts/swift_locked.sh build --target ShopPilot` once at end of slice.

Slice ≤90m.

---

## After all slices
- MASTER_KANBAN: 1800a–h `[x]` + worklogs; parent SPK-1800 `[x]` only if all eight AC + verifies.
- SPK-0623 remains `[ ]`.
- Laser remains held.
- Do not stamp 1700 done from this prompt.

Loop: never idle on `[!]`. If a file is locked by another agent, skip to a parallel-ok card (e/g/h) or wait — do not merge conflicting DesignCanvasView edits.
```

---

## Operator notes (not part of the paste)

- Dispatch **one** Hermes on this prompt **or** split: one agent on 1800a–d+f (DesignCanvasView), another on 1800e / 1800g / 1800h after 1800a — still **one swift_locked** compile at a time.
- BUG-03 remains P0 for Preview AX/capture; it is **not** a gate for snap.
- 1700 still `[ ]` on the board as of 2026-08-13 → **1800h = Model only**.
- Screenshot pack is 1700d, not 1800.
```
