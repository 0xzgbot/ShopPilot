# Agent prompt — SPK-1910 Trochoidal slotting

Paste this whole file into Hermes/Cursor as the job. North star: `AGENTS.md` + `docs/planning/LEAN_CNC_SCOPE.md`. Board: `MASTER_KANBAN.md` only. Do **not** invent extra strategies (dogbones, T-bones, 3D adaptive, Fusion rest) on this parent.

---

## What you are building

**Trochoidal slotting:** a Cut-stage toolpath that mills a **narrow slot / closed corridor** with looping (trochoid) motions so the bit never takes a full-width bury.

A conventional pocket/slot with tool diameter ≈ slot width is 100% radial engagement: chips pack, hobby GRBL routers stall, bits snap. A trochoid advances along the slot centerline while the cutter **circles** (or G2/G3 arcs) with a small **width of cut (WOC / stepover)**. Axial DOC can stay relatively deep; radial engagement stays small.

This is the MillMage “automatic trochoidal slotting” idea, implemented **independently** (no proprietary ports, no CRV). ShopPilot already has `PocketToolpathEngine` zigzag/spiral — **do not replace pocket**. This is a **new strategy**.

---

## Product rules (non-negotiable)

- Offline Mac app. GRBL-class G-code. No cloud. No auto-start stream.
- All Swift via `./scripts/swift_locked.sh`. Never `rm -rf .build`. Worktree-only `Sources` edits.
- One Swift compile at a time. If lock waits, heartbeat and wait.
- DoD per card: Engine + UI + Persist + Verify as specified. Never `[x]` for file-drop/build-only.
- Claim: `[ ]` → `[~]` + work log, then `[x]` + work log. Parent stays `[~]` until a–c are `[x]`.
- Assignee: `coder`. Max runtime **60m** per child. Parent `SPK-1910`.

---

## Geometry contract (v1 — keep it dumb and testable)

**In:** one or more **closed** `VectorPath`s (same type pocket uses). Treat the region as a **slot corridor**:

1. Offset the closed boundary inward by `toolRadius + 0.5 * minRadialEngagement` (or equivalent) to get a **centerline polyline** (medial-axis approximation OK: for a rectangle, centerline = long-axis segment inset from ends by tool radius).
2. If the inset region is empty or narrower than `toolDiameterMm * 1.02`, return `isTooNarrow = true` and **no cut moves** (status string, like pocket `isTooSmall`).
3. Along the centerline, emit **loops**:
   - Loop radius `R` derived from `maxWocMm` (radial engagement) and tool diameter. Typical: `R ≈ toolRadius - woc/2` for a circle whose chord peels `woc` off the wall — document the formula in a comment and **assert it in the CLT**.
   - Forward pitch `p` (mm per loop) = `loopPitchMm` (param, default ~0.4–1.0 × WOC).
   - Prefer **G2/G3 arcs** in the XY plane at constant Z for the circular part; G1 for short links. If arc fitting is painful, G1-chord approximation is OK **if** chordal error ≤ 0.05 mm (CLT).
4. **Z:** helical or ramped entry at slot start (reuse pocket `rampPlungeMoves` idea: no vertical plunge into full slot). Then **step-down passes** of `maxDepthOfCutMm` from `startDepthMm` to `cutDepthMm`. Retract to `safetyHeightMm` between passes (G0).
5. **Never emit M3 on generate unless** `spindleRpm > 0` (same discipline as Pocket SPK-1133b). No M6. No G28. Lines `\n`-terminated at post time like existing engines; engine returns `[String]` like `PocketToolpathEngine`.
6. Header marker: `O=TROCHOID_SLOT` (stable for goldens).
7. Climb vs conventional: reverse loop winding (`G2` vs `G3`) from `cutDirection`.

**v1 slot detection (explicit):**
- Prefer a **single closed rectangle** fixture (length ≫ width, width between `1.05×D` and `2.5×D`).
- Optional: a stadium / capsule polyline. **Do not** require general pockets with islands in v1.

**Out of engine v1:** open polylines, V-bits, 3D, rest-from-previous-tool, trochoidal **pocketing** of wide areas, aluminum-specific feeds, Fusion adaptive clearing.

---

## Params (`TrochoidSlotParams`) — Codable, legacy-safe

New file: `Sources/ShopPilotCore/TrochoidSlotToolpath.swift` (params + engine + result). Additive defaults so extra keys in JSON don’t break old jobs (there are no old jobs; still decode-unknown-keys-safe).

| Field | Default | Meaning |
| --- | --- | --- |
| `toolDiameterMm` | 6.0 | Cutter D |
| `cutDepthMm` | 6.0 | Final Z down from start |
| `startDepthMm` | 0.0 | |
| `maxDepthOfCutMm` | 2.0 | Z step |
| `maxWocMm` | 0.8 | Max radial engagement (the whole point) |
| `loopPitchMm` | 0.6 | Advance per loop along centerline |
| `feedRateMmPerMin` | 1000 | XY feed on loops |
| `plungeFeedRateMmPerMin` | 300 | Entry |
| `safetyHeightMm` | 5.0 | |
| `spindleRpm` | 0 | 0 = no M3 |
| `cutDirection` | climb | winding |
| `rampEntry` | true | no dead plunge |

Validate: all sizes > 0; `maxWocMm < toolDiameterMm`; `loopPitchMm > 0`. Invalid → empty gcode + errors array (pocket-style).

---

## Files / hot spots

**Wave A (new files only, parallel-ok):**
- `Sources/ShopPilotCore/TrochoidSlotToolpath.swift` — NEW
- `Sources/ShopPilotVerify1910a/main.swift` — NEW
- `Package.swift` — register CLT **before** or **with** engine (see 1900a pattern)

**Wave B (serial, hot files):**
- `Sources/ShopPilotCore/ToolpathTree.swift` — `StrategyKind.trochoidSlot`, `displayName` "Trochoid Slot", label prefix `"Trochoid Slot"` (must not collide with `"Thread Mill"`)
- Recalc switch that already branches pocket/profile — add trochoid recompute from `paramsJSON`
- `Sources/ShopPilot/AppSession.swift` — `generateTrochoidSlotToolpath()`, `applyTrochoidSlotParams`
- Cut menu + `TrochoidSlotParamsForm` next to `PocketParamsForm` in `ContentView.swift`
- Command palette id if others have `pocket_tp` — optional, not required for 1910b close
- Preview: existing toolpath playback consumes G-code strings — **no Metal**. If preview ignores unknown ops, still show the node in the tree.

Do **not** edit VectorPilot. Do **not** touch serial/streamer.

---

## Split cards (mandatory — do not implement as one epic)

File these on `MASTER_KANBAN.md` under a new **PHASE** or after SPK-1900, then run **one card at a time**.

### Parent — SPK-1910 **CAM** Trochoidal slotting

- DoD: Engine (loops + Z passes) + UI (Cut add + params form) + Persist (`paramsJSON` round-trip) + Verify (1910a CLT + 1910c structural gate).
- Deps: none. Lean-in: hobby GRBL slotting; MillMage gap from `docs/planning/research/MARKET_GAPS_2026.md`.
- Out of scope: dogbones, rest pockets, 3D adaptive, laser, machine probe.

### SPK-1910a **CAM** Engine + CLT — NEW FILES ONLY — 60m — parallel-ok

**AC:**
- `TrochoidSlotToolpathEngine.compute` on a closed 80×8 mm rectangle, D=6.35 mm, WOC=0.8, depth=4, DOC=2 → ≥1 Z pass of looping XY, `isTooNarrow == false`.
- Same rectangle 5 mm wide, D=6.35 → `isTooNarrow == true`, zero cut G1/G2/G3 (header-only OK).
- CLT estimates peak radial engagement **&lt; toolDiameter** on sampled loop points (document sampling).
- Params round-trip Codable; missing keys decode to defaults.
- `O=TROCHOID_SLOT` present; no `M6`, no `G28`; M3 only if rpm &gt; 0.

**Out of scope:** AppSession, SwiftUI, Package UI, preview.

**Verify:** `./scripts/verify_locked.sh ShopPilotVerify1910a`  
Then `./scripts/swift_locked.sh build --target ShopPilotCore` only if needed.

Pre-register `ShopPilotVerify1910a` in `Package.swift` + placeholder dir **before** a second agent touches Package.swift.

### SPK-1910b **CAM** Tree + session generate/apply + recalc — serial — 60m — deps: 1910a

**AC:**
- Cut → add “Trochoid Slot” creates tree node, `strategyKind == .trochoidSlot`, dirty/recalc regenerates from stored params (mutate WOC, recalc, G-code changes).
- Beginner mode: hide this strategy (same pattern as other pro ops / `beginnerHiddenIDs` if pocket stays visible — **hide trochoid in beginner**; it is a pro cut).
- Undo: generate is undoable like pocket.

**Out of scope:** fancy form layout; screenshot pack.

**Verify:** extend 1910a **or** new `ShopPilotVerify1910b` that builds a tree + `paramsJSON` without UI. Plus `./scripts/swift_locked.sh build --target ShopPilot`.

### SPK-1910c **UX** Params form + AX — serial — deps: 1910b — 45m

**AC:**
- Form fields: D, depth, WOC, pitch, feed, plunge, safe Z, ramp toggle. Apply writes params and regenerates.
- Control has `.accessibilityLabel` + `.isButton` on the Add menu item.
- Python gate `scripts/verify_1910c_trochoid.py` greps form + `TrochoidSlot` prefix + `O=TROCHOID_SLOT`.

**Out of scope:** feeds library auto-fill (separate P1 Tool DB card).

**Verify:** `python3 scripts/verify_1910c_trochoid.py` PASS + app target build.

---

## CLT assert groups (1910a — copy into main.swift)

1. Happy slot: 80×8 mm rect, D=6.35, WOC=0.8 → `gcodeLines` count ≫ header; contains G1 or G2/G3; Z reaches ≈ −cutDepth.
2. Too narrow: 80×5 mm, D=6.35 → too narrow, no XY feed moves at cut Z.
3. WOC smaller → more loops (or longer path) than larger WOC on same slot (monotonic length or loop count).
4. Two Z passes when depth=4, maxDOC=2.
5. Climb vs conventional: winding / G2 vs G3 differs.
6. Codable round-trip + decode `{}` / partial JSON.
7. Safety: no M6/G28; spindle gated.
8. Determinism: twice compute, identical `[String]`.

Print `ShopPilotVerify1910a: PASS — trochoid slot engine` on success.

---

## Safety / G-code hygiene

- Cut moves must not go above material without G0 at safe Z (same as pocket).
- Keep-out zones: if pocket respects keep-outs, trochoid **should skip or abort** when centerline intersects a keep-out (if that’s a 20-line reuse, do it in 1910b; else document “follow-up” and abort compute with a status — do not silently mill keep-outs).
- Units mm. `%.3f` words.
- Simulator-first; **do not** stream on generate.

---

## Definition of done (parent)

- [ ] 1910a CLT PASS
- [ ] 1910b node + recalc
- [ ] 1910c form + python gate
- [ ] App target `swift_locked.sh build --target ShopPilot`
- [ ] Work logs on all cards
- [ ] No full `scripts/test.sh` required for close (ad-hoc slice verify OK; note it)

---

## Orchestrator note

Wave A: one agent, new files only. Wave B/C: same agent or serialized — `AppSession.swift` / `ContentView.swift` / `ToolpathTree.swift` are hot.

If 1910a times out after files landed: verify CLT yourself; do not rewrite the engine.

---

## Hand-off block (copy below the line)

```
You are building ShopPilot at ~/Desktop/ShopPilot.
Read AGENTS.md safety + docs/planning/LEAN_CNC_SCOPE.md.
Implement SPK-1910 trochoidal slotting per docs/planning/SPK-1910_TROCHOIDAL_AGENT_PROMPT.md
Claim the first Ready child (1910a if engine missing).
One card. Engine+Verify first. All swift via swift_locked.sh. Never rm -rf .build.
Do not add dogbones, rest-pockets, adaptive 3D, or Fusion-style morph.
Loop: claim → AC → [x] + work log → next child. Never idle on [!].
```
