# Changelog

All notable changes to ShopPilot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Machine **DRO** from parsed MPos; Model **Orbit** (2.5D relief, not Fusion)

### Honest / held
- Preview is 2.5D heightfield, not Metal chips
- Laser / LightBurn **held** (not a product)
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
- Preview copy honesty (wireframe sim, not Metal GPU; camera = reference overlay)
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
