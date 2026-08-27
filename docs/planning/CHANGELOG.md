# Changelog

All notable changes to ShopPilot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.07] — 2026-08-27 (universal)

Personal-use zip: `dist/ShopPilot-0.07-macOS.zip` (`VERSION=0.07` in `scripts/package_app.sh` → `CFBundleShortVersionString`). Universal arm64 + x86_64, ad-hoc signed.

### Added — Phase Y: Cut quality bar (SPK-2100 / 2110 / 2120)

Product bar for this wave was **cut quality** — how V-carve, 3D and photo work actually *look* off the machine — not feature count. Research: [`CUT_QUALITY_RESEARCH_2026-08-25.md`](CUT_QUALITY_RESEARCH_2026-08-25.md).

- **Drop-cutter 3D finish + finish stepover** (SPK-2100a) — ball-nose compensation on `HeightfieldFinishEngine`; finish stepover default is now 10% of tool Ø (the documented 8–12% finish-quality band) instead of ~25%.
- **Finish 3D form + raster angle** (SPK-2100b) — Finish 3D gains an inspector form; raster lace runs 0° / 45° / 90° (0° output stays byte-identical to pre-2100b).
- **Scallop-leftover preview** (SPK-2100c) — honest `h ≈ s²/(8R)` cusp-height tint against the 0.02 mm shop band, live off the finish stepover.
- **Rest finish** (SPK-2100d) — `previousToolDiameterMm`: only the cusps and narrow valleys a previous larger ball could not reach get finish-machined. `0` is byte-stable vs plain finish.
- **Photo V-carve groove geometry** (SPK-2110a) — groove **width** now derives from V-angle + tip Ø + depth (`w = tip + 2·d·tan(θ/2)`); 45° default raster, luminance invert toggle, stepover defaults to 50% of the widest groove so adjacent grooves overlap.
- **Photo / litho two-pass** (SPK-2110b) — optional rough (~50%) + finish (8–12%) legs; lithophane leftover-thickness warning when `stock − maxDepth < minThickness`.
- **V-bit flat tip Ø** (SPK-2120a) — real V-bits are not infinitely sharp; wide-valley depth accounts for tip width. Default keeps existing goldens byte-stable.
- **Inlay rim order — V-walls then floor** (SPK-2120b) — inlay pockets cut the sloped V-walls first, then clear the floor with the endmill, as one program.
- **Crisp-letters medial cell preset** (SPK-2120c) — Valley form **Crisp Letters (0.2 mm cell)** button with a time warning below 0.5 mm (`MedialAxis.swift` algorithm untouched).

### Fixed — SPK-2120b audit: inlay V-first did not actually cut

An independent audit found SPK-2120b marked done with a **green CLT on the wrong object** — three real defects behind passing assertions:

- `InlayToolpathEngine.computePocket` built its `VCarveParams` without copying `vFirst` or enabling the clearance pass, so the inlay form toggle was **persist-only** and never reached the engine.
- The floor pass was appended **after** the first `M30`/`%`. GRBL halts at `M30`, so the floor would never be cut — while marker-presence assertions still passed.
- Once enabled, the floor section emitted its `O=` header with **zero cut moves**: `clearanceGcode` implements sign-board semantics (clear *around* protected letters), but an inlay pocket's interior *is* the floor. New `inlayFloorGcode` scanline-fills each closed vector inset by the tool radius, gated by `inlayInteriorFloor` (default off) so ordinary sign boards never pocket out their own letters.

### Added — PHASE Y verification audit

- **`ShopPilotVerifyPhaseYAudit`** (+ [`scripts/sweep_phasey.sh`](../../scripts/sweep_phasey.sh)) — phase-wide guard against the defect class above. Asserts on **emitted cut moves**, not markers or in-memory fields: cut moves are attributed to their owning `O=` section; each param is proved live by mutating it and diffing the G-code; exactly one `M30` with nothing after it but `%`; protected-region checks use full cut **spans**, not endpoints. Two self-check sentinels deliberately trip and roll back, so an all-green run cannot merely mean an inert harness.
- **Result: 47 assertions PASS — no dead params found.** Every PHASE Y param reaches the G-code, and byte-stability holds where promised. Phase sweep 17/17 PASS.

### Honest / held (this wave)
- Preview remains 2.5D heightfield. Laser / LightBurn held. **SPK-0623** remains owner-gated `[ ]`.

---

### Added — Phase S: PC-parity wave (SPK-1900)
- **Photo Lithophane** (SPK-1900a) — photo import → brightness/contrast/gamma/invert adjust → heightfield with two modes: lithophane thickness (light-transmission mapping) and grayscale relief (luminance→depth), three cut paths (lithophane finish-3D / grayscale rough+finish / Photo V-Carve handoff). Design-stage **Start from a Photo…** starter.
- **Frame job + click-to-jog** (SPK-1900b) — Frame sends a safe-Z G0 rectangle around job bounds; clicking the canvas jogs G0 to that XY. Both gated behind connected + Idle.
- **Beginner / Advanced experience mode** (SPK-1900c) — explicit mode switch in Preferences + Welcome; Beginner hides pro panels (Trochoid, Post Studio, etc.) without deleting them; three one-click job starters (Sign, Photo, 3D relief).
- **Safety chrome audit** (SPK-1900d) — Hold/Reset/connection state confirmed visible across all six stages while connected (audit recorded; no code change needed).
- **Image-to-Relief** (SPK-1900e) — bitmap → heightfield with auto-levels stretch, gaussian smoothing, detail boost (honest name: not "AI"). Model stage **From Image…**.
- **Nesting** (SPK-1900f) — shelf/skyline packer for sheet goods, rotation 0/90°, spacing + margins, deterministic order, overlap-free; wired to the Design stage Nest… action.
- **Open-source positioning** (SPK-1900g) — owner license decision pending (`[~]`; parent stays open).

### Added — Phase T: Trochoidal slotting (SPK-1910)
- New **Trochoid Slot** strategy (Cut → More): bounding-box medial-axis centerline for closed slot corridors, full-circle G2/G3 loops with ramp entry (no dead plunge), Z step-downs between passes, effective pitch ≤ radial engagement, too-narrow gate (< D×1.02). Engine + tree/session generate/recalc + params form; requires corridor selection when shapes are selected.

### Fixed — Dogfood sweep bugs (2026-08-22 walk, fixed 2026-08-23)
Report: [`DOGFOOD_REPORT_20260822.md`](DOGFOOD_REPORT_20260822.md).
- **Sign sample could never run** (SPK-DOGFOOD-01, P1) — Sign layout scaled 0.75 at payload build: sheet 600×400 → 450×300 mm, inside the default 500 mm simulator travel envelope. Previously every Run alarmed `Soft limit` within ~9 lines. Verify: `ShopPilotVerifyDOGFOOD01`.
- **Raw TX/RX console pinned main thread ~95% CPU during alarms** (SPK-DOGFOOD-02, P0) — chrome write guard (identical status polls no longer republish), windowed 80-row `ConsoleView`, stale-transport teardown on stream end/disconnect, `@MainActor` event handling killing the reconnect ABBA deadlock ("Connecting…" wedge). Alarm + raw mode now stays responsive indefinitely. Verify: `ShopPilotVerifyDOGFOOD02`, `ShopPilotVerifyDOGFOOD02b`.
- **Trochoid generate + big-buffer preview stalled main thread minutes-long** (SPK-DOGFOOD-03, P1) — O(n) peck-retract detection replaces O(candidates × lines²) rescans (14,803-line fixture with 6,800 retracts: 0.215 s); Trochoid Slot respects corridor selection. Verify: `ShopPilotVerifyDOGFOOD03`.
- **Preview lied "Material sim ready (0 cells)"** (SPK-DOGFOOD-04, P2) — nil-heightmap guard emits honest "Material sim empty — press Simulate". Verify: `scripts/verify_dogfood04_preview_status.py`.
- **AX driver crashed (SIGILL) at dump depth ≥7** (SPK-DOGFOOD-05, P2 tooling) — hardened CF casts in `scripts/ax_act.swift` (trap was `posOf` force-cast), iterative LIFO walk, depth-gated geometry queries, precompiled binary shipped as `scripts/ax_act_bin`. Depth-8/10 dumps exit 0.

### Honest / held
- Preview remains 2.5D heightfield. Laser / LightBurn held. **SPK-0623** remains owner-gated `[ ]`.

---

## [0.06] — 2026-08-13 (universal)

Personal-use zip: `dist/ShopPilot-0.06-macOS.zip` (`VERSION=0.06` in `scripts/package_app.sh` → `CFBundleShortVersionString`). Universal arm64 + x86_64, ad-hoc signed.

### Added — Preview playback (SPK-1700) + async Cut generate (SPK-UI-BUG-03)
- Filled sheet heightfield in Preview (no `/40` display stride); circular **bit-radius stamp** on G1 removal
- **Playhead / Play** over sim time (t=0 stock → t=1 full sim)
- Screenshot pack: `welcome.png`, `design.png`, `cut.png`, `2d-pocket-stepover.png`, `2d-playhead.png`, `3d-relief-sim.png`, `machine-sim.png`
- Cut **Cut out** generate off the main thread (no ~35s UI/AX freeze)

### Added — First-hour CAM UI (SPK-1800)
- Design: grid **snap**, **marquee** select, cursor **XY DRO**, sheet **origin** (corner/center)
- Cut inspector **F / S / Z**; tabs/leads overlay on Design
- Machine **DRO** from parsed MPos; Model **Orbit** (2.5D relief)

### Honest / held
- Preview is 2.5D heightfield.
- Laser / LightBurn **held**
- **SPK-0623** remains owner-gated `[ ]` (AX `ui_drive_full` PASS is evidence, not a ship stamp)

---

## [0.05] — built on request (universal)

### Added — Phase O (friendliness + live serial + persist-honesty, SPK-1400…1402)
- Welcome sheet: 4 bundled sample projects (one click → Design), real Open Job / Import paths
- Setup stage: Stock & Material first; Sheets/Double-sided/Rotary/Document Variables/Driven Dimensions/Golden Jobs under one Advanced disclosure
- Friendly, sentence-case stage copy; "Untitled Project" chrome
- Cut recipes: Cut out / Pocket / Engrave + More (all other strategies, Fixture G-code, Post Studio, Enqueue, Job Sheet)
- Coach strip as a tip card with runnable actions (Try a sample / Cut out / Connect) + empty-state rules for Model/Preview/Setup/Machine
- Inspector honesty: W/D/H bound to the active sheet; no Studio3D-only claims; clean selection names
- Live serial: UI port/baud → `open(config:)`, termios 8N1 at real baud, 250000 via IOSSIOSPEED, jog `\n` + G90 restore, `waitForOk` ALARM/timeout, single realtime writer (`!`/`~`/0x18 once), status `?` poll that pauses while streaming, one-writer write gate
- Autosave with recovery sheet ("Recover unsaved work?"), full-package payload (toolpaths survive crash), corrupt sheets surface instead of silent skip, honest Metal check
- Machine stage density: run controls under More; dead UI removed; one TransportFactory (Core)

### Added — Phase P (stream hygiene + AppSession split, SPK-1500…1509, 1403)
- Stream start never writes 0x18; fallback path attaches the streamer
- File menu Open Job… (⌘O) routes to the same session path as Welcome
- Simulator soft-limit follows the machine profile's travel (legacy 500 default)
- Preview copy honesty (wireframe sim; camera = reference overlay)
- AppSession split: sample-load lifecycle, snapshot undo, Cut-out generate, and fixture G-code facade extracted into Core/Geometry with CLT-verified delegates (facade + bindings unchanged)

### Fixed
- Bugbot review: autosave now persists the full package (toolpaths/groups/doc vars), sample load starts clean (no Save-over-previous), Welcome Open shows the real file picker

---

## [0.04] — unreleased (build on request)

### Added — Phase L (UX overhaul, SPK-1201…1210)
- Cut-Layers table (LightBurn-style sortable grid over the toolpath tree)
- Surface-color material preview (walnut/acrylic/painted-MDF/plywood palettes, depth-shaded)
- Smart part selection + canvas dimension handles
- Context menus everywhere (command registry shared with toolbars)
- Inline coach strip with first-run tooltips
- View gizmo + orthographic toggle (top/iso/front presets)
- Visual toolpath status dots + Recalc All
- Sheet duplication + toolpath transfer across sheets
- WebP import + recent-files rail
- Peck-drill visualization + toolpath-on-hover

### Added — Phase M (essential CAM, SPK-1301…1305)
- Dogbone corner relief (joinery)
- Feed-rate override (10–200%) + spindle control (M3 S/M5)
- Touch-off Z probing (G38.2 sequence + offset math)
- Work offsets G54–G59
- Rest machining (remaining-depth z-level passes)

### Added — Phase M ease-of-use (SPK-1311…1318)
- Toolpath templates (save/apply)
- Autosave (5-min) + crash recovery
- Sample projects pack (sign, box, keychain, plaque)
- **Async recalc** — dirty recalc off the main thread, no UI freeze
- Manufacturer tool presets (Amana/Whiteside catalog)
- Sheet-aware stock block in the preview
- Editable keyboard shortcuts + Preferences pane
- Job-sheet save/print from the Cut stage (generator existed; button added)

### Added — Phase N remaining gaps (SPK-1319…1325)
- 3D text relief (glyph raster → raised-letter heightfield)
- Acceleration-aware time estimates (trapezoidal velocity profile)
- Vector boundary (convex hull + offset)
- Design PDF export (CoreGraphics A4)
- Import torture — SVG/DXF hostile-input robustness proven by CLT
- Real serial wiring — port/baud pickers in the Machine stage
- Sweep WARN hygiene — all 15 exit-0-no-marker targets emit canonical PASS lines

### Added — Phase N visual wave (SPK-VIS-1…5)
- Custom app icon (programmatic router-bit mark, amber-on-graphite, bundled via `package_app.sh`)
- Brand accent tint applied app-wide (`SP.Tint.brand`)
- CNC-meaningful stage icons (verified to exist in SF Symbols)
- Material swatch chips in Setup (visible wood/acrylic)
- Design-anchored canvas grid + amber origin datum

### Changed
- Full regression sweep: **175 PASS / 0 FAIL / 0 WARN** (first WARN-free run, 2026-08-11)
- Permanent scope lock recorded: personal-use only; no 3D-view editing, no parametric modeling

---

## [0.03] — 2026-08-10

### Added — Phases I–K (production & power user)
- **Multi-sheet management** (SPK-0800) — sheets, active-sheet routing, duplication + toolpath transfer
- **Double-sided jobs** (SPK-0801) — front/back pairing, alignment, back-side Z offset
- **Array-copy toolpaths** (SPK-0803) + **advanced nesting** (SPK-0804) + **tiling manager** (SPK-0805)
- **Vector validator expanded** (SPK-0806) — real overlap-detection bug fixed
- **Driven dimensions** (SPK-0807) — parametric-lite expressions over document variables
- **Production golden jobs** (SPK-0808) — golden runs against real engines
- **Thread milling** (SPK-0902) — real helical engine; verify caught a Z-direction bug
- **Rotary job setup** (SPK-0903) + wrap/spiral strategies
- **Level mirror modes** (SPK-0908) + specialty/rotary/laser goldens (SPK-0909)
- **Post Studio** (SPK-1000) — user post templates with `$variable` blocks
- **Document variables everywhere** (SPK-1001) — expression-backed depth fields
- **Performance** (SPK-1003) — 10k vectors, large relief, no quadratic hotspots
- **JSON recipes + plugin ABI** (SPK-1006) — loadable sandboxed child-process plugins
- **Webcam overlay, multi-file queue, network bridges** (SPK-1008)
- **v2.0 ship checklist** (SPK-1010)

---

## [0.02] — 2026-08-05

### Changed
- Global UI shell overhaul: new shared design system (`DesignSystem.swift`) with spacing / radius / typography / motion / semantic-tint tokens used by every surface (top chrome, stage rail, browser, inspector, status bar, machine safety chrome)
- New top chrome bar with machine status bridge; alarm banner now routes to the Machine stage
- Browser, inspector, coach panel, and stage rail rebuilt on design tokens
- Command palette gains scale + opacity transitions
- Machine panel refactored around a `MachineChromeLink` state bridge with reusable jog / safety button components

### Added
- Versioned release packaging: `VERSION` and `ZIP_NAME` overrides in `scripts/package_app.sh`
- Release artifacts: `ShopPilot-0.01-macOS.zip` (first upload, universal arm64 + x86_64) and `ShopPilot-0.02-macOS.zip` (this build)

---

## [0.01] — 2026-08-01

### Added
- Native macOS app shell with SwiftUI (Phase B)
- Stage rail UI: Setup | Design | Model | Cut | Preview | Machine
- Document model v0: Job, Sheet, Layer, undo, dirty doc
- Save/open `.shoppilot` package format with autosave and crash recovery
