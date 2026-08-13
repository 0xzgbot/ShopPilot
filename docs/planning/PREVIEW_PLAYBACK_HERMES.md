# Hermes mega-prompt — Vectric-like Preview playback (SPK-1700) + BUG-03 first

Copy everything below the line into one Hermes session. Outer wall-clock may be long; **implement internally as 45–90 minute slices**. Do **not** rubber-stamp SPK-0623. Laser/LightBurn is **held**. Simulator only — never live serial jobs.

---

```
You are a coding agent on ShopPilot at ~/Desktop/ShopPilot (personal-use Mac CNC — no App Store/notarize).

North star: docs/planning/LEAN_CNC_SCOPE.md
Board: MASTER_KANBAN.md
Safety: AGENTS.md §2 (Hold/Reset always visible when connected; no auto-start stream; simulator-first)
UI doctrine: 6-stage rail Setup → Design → Model → Cut → Preview → Machine; palettes + inspector; ≤12 icons per stage; no NavigationSplitView rewrite; no icon walls.
Prompt file: docs/planning/PREVIEW_PLAYBACK_HERMES.md
Screenshot pack: docs/screenshots/README.md

## Hard rules
- Claim cards `[ ]` → `[~]` then `[x]` + Work log. Never `[x]` without Engine + UI + Persist + Verify for that slice.
- Worktree-only Sources edits (git worktree under .worktrees/ or repo convention). Do not edit the user's dirty main tree if a worktree exists.
- ALL Swift: `./scripts/swift_locked.sh` or `./scripts/verify_locked.sh`. NEVER `rm -rf .build`. NEVER full-package `swift test`. CLT has no XCTest.
- One swift compile at a time (lock). Prefer `--max-runtime 45m` or `60m` per slice.
- Out of scope globally: laser/LightBurn product, Metal chip sim, App Store, SPK-0623 `[x]`, live CNC / real serial job (SimulatorTransport only).
- Parent SPK-1700 stays `[ ]` until 1700a–d are `[x]` and screenshots exist. Do NOT mark SPK-0623 done.

## ORDER (mandatory)

### 0) SPK-UI-BUG-03 FIRST (P0) — async Cut generate
Card: SPK-UI-BUG-03 on MASTER_KANBAN.

Problem: Cut **"Cut out"** calls `AppSession.generateProfileToolpath()` → `ProfileToolpathGenerator.generateProfile(on:)` → `ProfileToolpathEngine.compute` on the **main thread** (~35s on Sign sample). AX blackout / beachball.

Fix: Route **new** Profile/Pocket/etc. generate (at least `generateProfileToolpath` and any sibling Cut buttons that call engines synchronously) through the existing **SPK-1314 async pattern**: `recalculateDirtyToolpathsAsync` — background `computeDirtyToolpathResults` (or equivalent generate) + main-actor apply. Keep `ShopPilotVerify1403c` source-contract passing if you touch the generator protocol.

AC:
- Cut out does not block the main thread for engine compute.
- UI stays responsive (Cancel / stage rail / AX queries) during generate.
- Result still lands on the toolpath tree + G-code buffer as today.

Out of scope: engine perf tuning; changing Profile semantics; preview playback.

Verify: existing generator/contract CLTs that still apply (`ShopPilotVerify1403c` if touched) + a new thin CLT or python grep proving generate is dispatched off-main (e.g. `DispatchQueue.global` / `Task.detached` around compute, not a sync `compute` on the Cut button path). Then `./scripts/swift_locked.sh build --target ShopPilot`.

Work log + `[x]` BUG-03 before starting 1700a.

---

### 1) SPK-1700a — filled heightfield raster (drop /40 display stride)
Parent: SPK-1700.

Today: `ToolpathSimulator.materialSimulation` / `draftHeightSamples` subsample with `max(1, hm.width / 40)` and `ToolpathPreviewView` draws **4×4 ellipses** per sample (sparse dots). Vectric-like Preview needs a **filled** raster of the full heightmap.

AC:
1. Preview heightfield/combined modes draw the **full** heightmap as a filled image (NSImage/CGImage from cell colors, or Canvas rects at **cell size**, not a 40-stride scatter). Display stride default **1** (every cell). Keep optional coarse stride only for draft if you must, but **Simulate** (material sim) must be dense.
2. Sheet bounds still match the job sheet; material palette tint (SPK-1202) still applies.
3. `ShopPilotVerify1103e` still PASS (cancel, sheet-aware, full-tree). Add `ShopPilotVerify1700a`: a pocket/raster G-code fixture produces a heightmap whose **sample count ≈ width×height** (not ~40×40), and removed cells are contiguous trenches not isolated dots.

Files (typical): `Sources/ShopPilotCore/ToolpathSimulator.swift` (`sampleStride` default 1 for materialSimulation display path; may return Heightmap not only sparse tuples), `Sources/ShopPilot/ToolpathPreviewView.swift` (draw image/grid). Persist: none required beyond in-memory sim.

Out of scope: playhead, bit-radius stamp, screenshots, Metal.

Verify: `./scripts/verify_locked.sh ShopPilotVerify1103e` then `./scripts/verify_locked.sh ShopPilotVerify1700a`. Register target in Package.swift.

Slice ≤90m.

---

### 2) SPK-1700b — playhead / slider over sim time
Parent: SPK-1700. Deps: 1700a.

AC:
1. Preview toolbar: slider (and optional Play/Pause) over **simulation time / G-code progress** (0…1 or 0…N lines). Scrubbing shows heightfield **as of that prefix** of the toolpath (prefix simulate or cached snapshots — your call; prefix-sim on scrub is OK if cancellable).
2. Combined/heightfield updates with playhead; wireframe may still show full path.
3. `ShopPilotVerify1700b`: prefix of a 3-line cut removes less (or equal) material than the full path; t=0 ≈ stock top; t=1 matches full sim.

Out of scope: bit stamp (1700c); window screenshots (1700d); Metal.

Verify: `./scripts/verify_locked.sh ShopPilotVerify1700b` + regression `ShopPilotVerify1103e`.

Slice ≤90m.

---

### 3) SPK-1700c — circular bit-radius stamp
Parent: SPK-1700. Deps: 1700a.

Today: `simulate()` sets **one cell** at the tool XY to currentZ. Stepover ridges look like a 1-cell needle, not an endmill.

AC:
1. At each interpolated point along G1 (when Z below stock), stamp a **disk** of radius = tool radius (from session/tool DB / G-code comment / param — use assigned tool diameter/2, fallback 1.5–3.2 mm documented in verify). Every cell whose center is within radius is lowered to min(current, cutter Z) as a flat endmill (v0). Ball-nose optional, not required.
2. Raster pocket stepover ridges **match tool diameter** (gap between passes ≈ stepover, trench width ≈ diameter).
3. `ShopPilotVerify1700c`: a G1 along X at Z below stock with radius R clears a band ≈ 2R wide in Y, not a 1-cell line.

Out of scope: true 3D ball-nose cusp shading; laser; Metal chips.

Verify: `./scripts/verify_locked.sh ShopPilotVerify1700c` + `ShopPilotVerify1103e`.

Slice ≤90m.

---

### 4) TEST + SCREENSHOTS — SPK-1700d
Parent: SPK-1700. Deps: 1700a, 1700b, 1700c. BUG-03 must already be `[x]`.

Build: `./scripts/swift_locked.sh build --product ShopPilot` (or `--target ShopPilot`). Launch Simulator-only.

**2D cut**
- Welcome sample **or** Design rectangle → Cut **Pocket** (or Profile/Cut out if pocket UX is slower) → wait for async generate (BUG-03) → Preview → **Simulate**.
- Heightfield: filled pocket, visible stepover consistent with bit stamp.
- Capture with `scripts/capture_window.swift <pid> docs/screenshots/<name>.png`

**3D cut**
- Plaque sample **or** Design → STL Relief / Model heightfield → **Rough 3D** (and Finish 3D if one extra shot is free) → Simulate.
- Capture relief sim showing heightfield (not empty canvas, not Metal chip pile).

**Required files** (see docs/screenshots/README.md for composition):
- docs/screenshots/2d-pocket-stepover.png
- docs/screenshots/2d-playhead.png
- docs/screenshots/3d-relief-sim.png
- docs/screenshots/welcome.png
- docs/screenshots/design.png
- docs/screenshots/cut.png
- docs/screenshots/machine-sim.png

Keep existing `01-setup.png` … `06-preview.png` unless a new shot is a strict replacement; if you replace `06-preview.png`, it must show filled heightfield.

Then update **root README.md** image markdown to point at the new pack (and keep honest captions). Update `docs/screenshots/README.md` checkboxes if present.

Verify: files exist and are non-tiny PNGs (`file` + size > 20KB each). `./scripts/verify_locked.sh ShopPilotVerify1103e` still PASS. Do not claim SPK-0623.

Machine shot: **Simulator** connected, **Hold** and **Reset** visible. Never Serial.

---

## After all slices
- MASTER_KANBAN: 1700a–d `[x]` + worklogs; parent SPK-1700 `[x]` only if DoD met (filled raster + playhead + bit stamp + screenshot pack + verifies).
- SPK-0623 remains `[ ]`.
- Laser remains held.

Loop: never idle on `[!]`. If blocked on TCC for capture, write shots you can + note Screen Recording permission in Work log — still do not fake PNGs.
```

---

## Operator notes (not part of the paste)

- Dispatch **one** Hermes on this prompt; serialize Swift via `swift_locked`.
- BUG-03 is P0 and must land before Preview UI work that needs Cut generate under AX/capture.
- Screenshot composition details live in `docs/screenshots/README.md`.
