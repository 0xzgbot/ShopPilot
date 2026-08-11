# ShopPilot v2.0 — Ship Checklist (SPK-1010)

**Status:** Tracking — completed 2026-08-11 (Phases I–N + visual wave all closed).
**Gate:** every item below is `[x]` only when its Engine + UI + Persist + Verify
CLT are in place (the same DoD as v1). Human `[!]` items stay unchecked.

---

## 1. Phase I — Production & dual-side (v1.2)

- [x] **SPK-0800 Multi-sheet management** — Job.sheets + active-sheet routing
      (layers/design/toolpaths follow the active sheet), Setup-stage sheet list,
      `activeSheetID` persisted. Verify: `ShopPilotVerify0800` PASS.
- [x] **SPK-0801 Double-sided job** — front/back pairing with alignment method,
      back-side Z offset from stock thickness, flip-side surface switching.
      Verify: `ShopPilotVerify0801` PASS.
- [x] **SPK-0802 Inlay pocket/plug + V-Carve recipes** — shipped earlier
      (2026-08-05 lean slices).
- [x] **SPK-0803 Array-copy toolpath + merged toolpath** — real G-code
      transform engine (linear/angle/circular arrays, merge in tree order with
      markers). Verify: `ShopPilotVerify0803` PASS.
- [x] **SPK-0804 Nest advanced** — Geometry guillotine engine, placed copies
      materialize as design vectors. Verify: `ShopPilotVerify0804` PASS.
- [x] **SPK-0805 Tiling manager** — rows×columns grid with gap/alignment/stagger.
      Verify: `ShopPilotVerify0805` PASS.
- [x] **SPK-0806 Vector validator expanded** — full rule set wired to the
      Validate All panel; **real overlap-detection bug fixed** (perpendicular
      segments were falsely flagged). Verify: `ShopPilotVerify0806` PASS.
- [x] **SPK-0807 Driven dimensions** — parametric-lite expressions over doc
      variables, live values, persisted. Verify: `ShopPilotVerify0807` PASS.
- [x] **SPK-0808 Production golden jobs** — golden runs against the REAL
      engines (replaced the `Double.random` stub): measured cut-span vs
      expected dims within tolerance, honest pass/fail counters.
      Verify: `ShopPilotVerify0808` PASS.

## 2. Phase J — Rotary / laser / specialty (v1.3)

- [x] **SPK-0900 Fluting / prism / chamfer / texture** — shipped earlier.
- [x] **SPK-0901 Photo V-Carve + Sketch carving** — shipped earlier.
- [x] **SPK-0902 Thread milling** — real helical engine (G2 pitch-per-revolution
      descent, internal/external radius, multi-pass); **verify caught the helix
      climbing up instead of cutting down** — fixed. Verify: `ShopPilotVerify0902` PASS.
- [x] **SPK-0903 Rotary job setup** — full Setup-stage rotary config
      (stock Ø / axis length / direction / wrap) persisted on the Job;
      wrap + fluting strategies default their Ø from it. Verify: `ShopPilotVerify0903` PASS.
- [x] **SPK-0904 Wrap 2D + spiral** — shipped earlier (wrap-2D).
- [x] **SPK-0906 Laser cut/fill/picture** — shipped earlier (real laser G-code).
- [x] **SPK-0907 Keyhole / rounding / drag knife** — shipped earlier.
- [x] **SPK-0908 Level mirror modes** — real heightfield grid mirror
      (X / Y / both), world footprint fixed, double-mirror identity.
      Verify: `ShopPilotVerify0908` PASS.
- [x] **SPK-0909 Specialty + rotary + laser goldens** — hand-derived byte-exact
      goldens for laser cut/engrave, rotary wrap X→A + CW/CCW, drag-knife blade
      offset, thread-mill pitch math. Verify: `ShopPilotVerify0909` PASS.

## 3. Phase K — Power user & distribution (v2.0)

- [x] **SPK-1000 Post Studio** — user post templates persisted (UserDefaults),
      `$variable` blocks resolved at export from the live document, Studio UI
      (list + editor + variable surface); export picker now includes user
      templates. Verify: `ShopPilotVerify1000` PASS.
- [x] **SPK-1001 Full document variables everywhere** — the SPK-0209 expression
      engine now backs Pocket/Drill/V-Carve depth fields (shared
      `DocVarCalcRow`), plus the existing Profile calc rows and job-setup stock
      dims. Verify: `ShopPilotVerify1001` PASS.
- [x] **SPK-1003 Performance: 10k vectors, large relief** — measured:
      10k transform 0.01s, 1k offsets 0.02s, 512×512 mirror 0.19s, 20k samples
      0.01s, 500-vector profile 0.81s — no quadratic hotspots.
      Verify: `ShopPilotVerify1003` PASS.
- [x] **SPK-1006 JSON recipe format + samples + plugin API draft** — `JobRecipe`
      Codable + `RecipeJSONCodec` (single / pack / envelope), 4 sample files in
      `fixtures/recipes/`, plugin API in `docs/planning/RECIPE_PLUGIN_API_DRAFT.md`.
      Verify: `ShopPilotVerify1006` PASS.
- [x] **Plugin ABI loadable (SPK-1006 follow-up)** — the draft is now a working
      ABI: `PluginStore` discovery (Application Support + bundle + fixtures),
      `PluginRunner` child-process sandbox with timeout kill, `PluginJobDocument` /
      `PluginOutput` JSON contract, bundled sample plugin
      (`fixtures/plugins/dotgrid-engrave/`), Cut-stage Plugins panel + session
      `runPluginStrategy`. Verify: `ShopPilotVerifyPluginABI` PASS (runs the real
      child process, 12-dot grid on 40×30 stock).
- [x] **SPK-1008 Webcam overlay, multi-file queue, network bridges** — Preview
      camera overlay (AVFoundation, graceful no-camera), sequential run queue
      (Enqueue / Next / Clear in Cut), persisted network-bridge config with
      validation. Verify: `ShopPilotVerify1008` PASS.
- [x] **SPK-1010 v2.0 ship checklist** — this document.

## 4. Phase L — UX overhaul (v2.1)

- [x] **SPK-1201 Cut-Layers table** — LightBurn-style sortable grid over the toolpath tree (✓ | status | # | name | tool | feed | depth | time), inline edit, drag reorder. Verify: `ShopPilotVerify1201` PASS.
- [x] **SPK-1202 Surface-color material preview** — MaterialSurfacePalette presets (walnut/acrylic/painted MDF/plywood), depth-shaded renderer. Verify: `ShopPilotVerify1202` PASS.
- [x] **SPK-1203 Smart selection + dimension handles** — PartDetector (closed shapes sharing an edge = one part), DimensionHandle drag math. Verify: `ShopPilotVerify1203` PASS.
- [x] **SPK-1204 Context menus** — CommandContext registry (action + enabled predicate), right-click on tree rows/layers/canvas/toolpaths. Verify: `ShopPilotVerify1204` PASS.
- [x] **SPK-1205 Coach strip** — CoachRuleEngine (stage + selection + dirty + preflight → tip). Verify: `ShopPilotVerify1205` PASS.
- [x] **SPK-1206 View gizmo + ortho** — ViewOrientation presets, nav cube, ⌘⌥1…4. Verify: `ShopPilotVerify1206` PASS.
- [x] **SPK-1207 Toolpath status + Recalc All** — ToolpathStatusEngine (stale/current/error), status dots, recalc-all. Verify: `ShopPilotVerify1207` PASS.
- [x] **SPK-1208 Sheet dup + transfer** — SheetOperations deep-copy with new UUIDs, toolpath re-parenting. Verify: `ShopPilotVerify1208` PASS.
- [x] **SPK-1209 WebP + recent rail** — ImageIO WebP decode, RecentFilesStore (cap 10, dedupe). Verify: `ShopPilotVerify1209` PASS.
- [x] **SPK-1210 Peck viz + hover** — peck retract detection, per-node segment tags, hover row → canvas highlight. Verify: `ShopPilotVerify1210` PASS.

## 5. Phase M — essential CAM + ease-of-use (2026-08-10)

- [x] **SPK-1301 Dogbone corner relief** — Dogbone.cornerReliefs on the 45° bisector. Verify: `ShopPilotVerify1301` PASS.
- [x] **SPK-1302 Feed override + spindle** — FeedRateOverride (10–200%), SpindleCommand (M3 S/M5/S). Verify: `ShopPilotVerify1302` PASS.
- [x] **SPK-1303 Touch-off probing** — TouchOff.plan/gcode/zOffset (G38.2 + G54 math). Verify: `ShopPilotVerify1303` PASS.
- [x] **SPK-1304 Work offsets G54–G59** — WorkOffsetRegistry (6 Codable slots). Verify: `ShopPilotVerify1304` PASS.
- [x] **SPK-1305 Rest machining** — RestRoughing.planRestPasses (remaining-depth grid → z passes). Verify: `ShopPilotVerify1305` PASS.
- [x] **SPK-1311 Toolpath templates UI** — built-but-unplugged ToolpathTemplateManager wired into Cut. Verify: `ShopPilotVerify1311` PASS.
- [x] **SPK-1312 Autosave + recovery** — built-but-unplugged Autosaver instantiated (5-min), crash-recovery notice. Verify: `ShopPilotVerify1312` PASS.
- [x] **SPK-1313 Sample projects** — 4 bundled examples + Welcome picker. Verify: `ShopPilotVerify1313` PASS.
- [x] **SPK-1314 Async recalc** — pure compute/apply split; dirty recalc off-main. Verify: `ShopPilotVerify1314` PASS.
- [x] **SPK-1315 Manufacturer presets** — Amana/Whiteside catalog importable. Verify: `ShopPilotVerify1315` PASS.
- [x] **SPK-1316 Sheet-aware stock** — preview draws the actual sheet block under toolpaths. Verify: `ShopPilotVerify1316` PASS.
- [x] **SPK-1317 Editable shortcuts** — ShortcutRegistry + Preferences Menu Shortcuts pane. Verify: `ShopPilotVerify1317` PASS.
- [x] **SPK-1318 Job sheets** — save/print button (generator existed). Verify: pre-existing (SPK-1135).

## 6. Phase N — remaining gaps + visual wave (2026-08-11)

- [x] **SPK-1319 3D text relief** — ReliefText3D glyph raster → raised-letter heightfield. Verify: `ShopPilotVerify1319` PASS.
- [x] **SPK-1320 Accel-aware time estimates** — MachineAccelProfile + AccelTimeEstimator (trapezoidal profile). Verify: `ShopPilotVerify1320` PASS.
- [x] **SPK-1321 Vector boundary** — convex hull + centroid-ray offset. Verify: `ShopPilotVerify1321` PASS.
- [x] **SPK-1322 Design PDF export** — CoreGraphics A4 render, %PDF-validated. Verify: `ShopPilotVerify1322` PASS.
- [x] **SPK-1323 Import torture** — SVG/DXF hostile-input CLT. Verify: `ShopPilotVerify1323` PASS.
- [x] **SPK-1324 Real serial wiring** — port/baud pickers threaded through connect() → SerialConfig.
- [x] **SPK-1325 Sweep WARN hygiene** — all 15 no-marker targets emit canonical PASS lines (sweep: 0 WARN).
- [x] **SPK-VIS-1 App icon** — programmatic router-bit mark, .icns bundled by `package_app.sh`.
- [x] **SPK-VIS-2 Brand accent** — SP.Tint.brand applied app-wide.
- [x] **SPK-VIS-3 Stage icons** — CNC-meaningful rail glyphs, verified in SF Symbols.
- [x] **SPK-VIS-4 Material swatch chips** — tappable wood/acrylic chips in Setup.
- [x] **SPK-VIS-5 Canvas grid + origin** — design-anchored grid + amber datum cross.

## 7. Human / deferred items (remain open)

- [ ] **SPK-0419** live hardware air-cut on a real router (needs hardware).
- [ ] ~~**SPK-0010** interviews~~ — permanently deferred: personal-use only, never for sale (no pricing/commercialization).
- [ ] **SPK-1009** App Store submission — deferred (personal use).

## 8. Verification gate

- Every `ShopPilotVerify*` target above passes via `./scripts/verify_locked.sh`.
- Whole-package `swift build` green.
- Regression sweep: the full `ShopPilotVerify*` set stays green after this wave
  (see MASTER_KANBAN work log for the sweep count).
