# ShopPilot v2.0 — Ship Checklist (SPK-1010)

**Status:** Tracking — completed 2026-08-10 wave closes Phases I–K feature backlog.
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

## 4. Human / deferred items (remain open)

- [ ] **SPK-0010** interviews (optional for v1; required before v2 pricing).
- [ ] **SPK-0419** live hardware air-cut on a real router (needs hardware).
- [ ] **SPK-1009** App Store submission — deferred (personal use).

## 5. Verification gate

- Every `ShopPilotVerify*` target above passes via `./scripts/verify_locked.sh`.
- Whole-package `swift build` green.
- Regression sweep: the full `ShopPilotVerify*` set stays green after this wave
  (see MASTER_KANBAN work log for the sweep count).
