# ShopPilot Shakedown Report — 2026-08-05

**Conductor:** Hermes coder (SPK-SHAKEa…i, overnight shakedown)  
**App:** `.build/debug/ShopPilot` @ `998a7ee` (master, clean)  
**Transport:** Simulator only. **Scope exclusions:** live CNC, notarization, App Store.  
**Run dir:** `/tmp/shoppilot-shake-ui-20260805/shots/`

---

## Verdict summary

| Area | Result | Notes |
| --- | --- | --- |
| CLT sweep (78 ShopPilotVerify*) | **PASS** | 78/78 PASS, 0 FAIL, 0 WARN. One fix: 1104c CLT stale (6→7 preflight items). |
| Import-torture fixtures | **PASS** | 28/28 checks PASS. |
| G1-A Setup → Design → Cut → Preview → Machine | **PARTIAL** | Decorative Panel recipe produced 0 vectors; Machine ran built-in air-cut (11 lines), not recipe handoff. Post-stream state bug (SPK-UI607) found + fixed in-loop. |
| G1-B Sign → V-Carve | **PASS (native AX walk 2026-08-05, Hermes)** | Full Signage recipe walk driven via AX: Setup → Signage → Design (glyphs + border, no Import panel — UI605 fix confirmed on-screen) → Cut (V-Carve 1 (Recipe) node, "All toolpaths up to date") → Preview (path in-sheet) → Machine (Simulator, connect, load 403 lines **zero auto-run**, Hold/Resume/Reset visible, preflight ack → Run → stream 394/394 → **checklist returns, big RUN gone — UI607 re-verified**). One new a11y bug found + fixed in-loop (SPK-UI608). |
| G1-C Dirty export gate | **PASS (CLT-proven)** | SPK-0603 CLT proves dirty blocks export + expert override. No in-app trigger (no dirty toolpaths). |
| G1-D V-Carve open-vector block | **PASS (CLT-proven)** | SPK-0604 CLT proves open vectors block V-Carve. No in-app trigger (no open vectors). |
| G1-E Stage density + safety chrome | **PASS** | 6 stage rail buttons ≤12 per stage; Hold/Resume/Reset visible when connected. |
| G1-F Model stage | **PASS** | Rough 3D / Finish 3D buttons present; empty-state CTA; Studio3D note informational. |
| G2 Tutorial walk | **DOCS FIXED** | SPK-UI604 [x]; optional re-walk. |
| **SPK-0623** | **LEFT [ ]** | **Owner decision after Signage glance + this report.** |

---

## CLT table (78 targets — all PASS)

| Target | Result | Log |
| --- | --- | --- |
| import-torture fixtures | PASS | logs/import_torture.log |
| ShopPilotVerify0201b | PASS | logs/ShopPilotVerify0201b.log |
| ShopPilotVerify0203c | PASS | logs/ShopPilotVerify0203c.log |
| ShopPilotVerify0210 | PASS | logs/ShopPilotVerify0210.log |
| ShopPilotVerify0211 | PASS | logs/ShopPilotVerify0211.log |
| ShopPilotVerify0308 | PASS | logs/ShopPilotVerify0308.log |
| ShopPilotVerify0310a | PASS | logs/ShopPilotVerify0310a.log |
| ShopPilotVerify0312 | PASS | logs/ShopPilotVerify0312.log |
| ShopPilotVerify0314a | PASS | logs/ShopPilotVerify0314a.log |
| ShopPilotVerify0318 | PASS | logs/ShopPilotVerify0318.log |
| ShopPilotVerify0319 | PASS | logs/ShopPilotVerify0319.log |
| ShopPilotVerify0404a | PASS | logs/ShopPilotVerify0404a.log |
| ShopPilotVerify0404c | PASS | logs/ShopPilotVerify0404c.log |
| ShopPilotVerify0412a | PASS | logs/ShopPilotVerify0412a.log |
| ShopPilotVerify0415 | PASS | logs/ShopPilotVerify0415.log |
| ShopPilotVerify0417a | PASS | logs/ShopPilotVerify0417a.log |
| ShopPilotVerify0418 | PASS | logs/ShopPilotVerify0418.log |
| ShopPilotVerify0500 | PASS | logs/ShopPilotVerify0500.log |
| ShopPilotVerify0600 | PASS | logs/ShopPilotVerify0600.log |
| ShopPilotVerify0601 | PASS | logs/ShopPilotVerify0601.log |
| ShopPilotVerify0603 | PASS | logs/ShopPilotVerify0603.log |
| ShopPilotVerify0604 | PASS | logs/ShopPilotVerify0604.log |
| ShopPilotVerify1100 | PASS | logs/ShopPilotVerify1100.log |
| ShopPilotVerify1101 | PASS | logs/ShopPilotVerify1101.log |
| ShopPilotVerify1101FlipH | PASS | logs/ShopPilotVerify1101FlipH.log |
| ShopPilotVerify1101b | PASS | logs/ShopPilotVerify1101b.log |
| ShopPilotVerify1101d | PASS | logs/ShopPilotVerify1101d.log |
| ShopPilotVerify1101e | PASS | logs/ShopPilotVerify1101e.log |
| ShopPilotVerify1101f | PASS | logs/ShopPilotVerify1101f.log |
| ShopPilotVerify1101g | PASS | logs/ShopPilotVerify1101g.log |
| ShopPilotVerify1101h | PASS | logs/ShopPilotVerify1101h.log |
| ShopPilotVerify1101i | PASS | logs/ShopPilotVerify1101i.log |
| ShopPilotVerify1101j | PASS | logs/ShopPilotVerify1101j.log |
| ShopPilotVerify1101k | PASS | logs/ShopPilotVerify1101k.log |
| ShopPilotVerify1102c | PASS | logs/ShopPilotVerify1102c.log |
| ShopPilotVerify1102d | PASS | logs/ShopPilotVerify1102d.log |
| ShopPilotVerify1102e | PASS | logs/ShopPilotVerify1102e.log |
| ShopPilotVerify1102f | PASS | logs/ShopPilotVerify1102f.log |
| ShopPilotVerify1102g | PASS | logs/ShopPilotVerify1102g.log |
| ShopPilotVerify1102h | PASS | logs/ShopPilotVerify1102h.log |
| ShopPilotVerify1102i | PASS | logs/ShopPilotVerify1102i.log |
| ShopPilotVerify1103 | PASS | logs/ShopPilotVerify1103.log |
| ShopPilotVerify1103a | PASS | logs/ShopPilotVerify1103a.log |
| ShopPilotVerify1103c | PASS | logs/ShopPilotVerify1103c.log |
| ShopPilotVerify1103d | PASS | logs/ShopPilotVerify1103d.log |
| ShopPilotVerify1103e | PASS | logs/ShopPilotVerify1103e.log |
| ShopPilotVerify1104 | PASS | logs/ShopPilotVerify1104.log |
| ShopPilotVerify1104a | PASS | logs/ShopPilotVerify1104a.log |
| ShopPilotVerify1104b | PASS | logs/ShopPilotVerify1104b.log |
| ShopPilotVerify1104c | PASS | logs/ShopPilotVerify1104c.log |
| ShopPilotVerify1104d | PASS | logs/ShopPilotVerify1104d.log |
| ShopPilotVerify1106a | PASS | logs/ShopPilotVerify1106a.log |
| ShopPilotVerify1106b | PASS | logs/ShopPilotVerify1106b.log |
| ShopPilotVerify1120 | PASS | logs/ShopPilotVerify1120.log |
| ShopPilotVerify1123 | PASS | logs/ShopPilotVerify1123.log |
| ShopPilotVerify1125 | PASS | logs/ShopPilotVerify1125.log |
| ShopPilotVerify1130 | PASS | logs/ShopPilotVerify1130.log |
| ShopPilotVerify1131 | PASS | logs/ShopPilotVerify1131.log |
| ShopPilotVerify1132 | PASS | logs/ShopPilotVerify1132.log |
| ShopPilotVerify1133 | PASS | logs/ShopPilotVerify1133.log |
| ShopPilotVerify1133b | PASS | logs/ShopPilotVerify1133b.log |
| ShopPilotVerify1136a | PASS | logs/ShopPilotVerify1136a.log |
| ShopPilotVerify1136b | PASS | logs/ShopPilotVerify1136b.log |
| ShopPilotVerify1136c | PASS | logs/ShopPilotVerify1136c.log |
| ShopPilotVerify1136d | PASS | logs/ShopPilotVerify1136d.log |
| ShopPilotVerify1137 | PASS | logs/ShopPilotVerify1137.log |
| ShopPilotVerify3DGolden | PASS | logs/ShopPilotVerify3DGolden.log |
| ShopPilotVerify3DRest | PASS | logs/ShopPilotVerify3DRest.log |
| ShopPilotVerify3DUI | PASS | logs/ShopPilotVerify3DUI.log |
| ShopPilotVerify3Da | PASS | logs/ShopPilotVerify3Da.log |
| ShopPilotVerify3Db | PASS | logs/ShopPilotVerify3Db.log |
| ShopPilotVerifyFMR013 | PASS | logs/ShopPilotVerifyFMR013.log |
| ShopPilotVerifyFMR014 | PASS | logs/ShopPilotVerifyFMR014.log |
| ShopPilotVerifyFMR016 | PASS | logs/ShopPilotVerifyFMR016.log |
| ShopPilotVerifyFMR019 | PASS | logs/ShopPilotVerifyFMR019.log |
| ShopPilotVerifyGolden25D | PASS | logs/ShopPilotVerifyGolden25D.log |
| ShopPilotVerifyProfileToolpath | PASS | logs/ShopPilotVerifyProfileToolpath.log |
| ShopPilotVerifyUI601 | PASS | logs/ShopPilotVerifyUI601.log |
| ShopPilotVerifyVCarveClear | PASS | logs/ShopPilotVerifyVCarveClear.log |

### Fix applied during sweep

| Target | Issue | Fix |
| --- | --- | --- |
| ShopPilotVerify1104c | Expected 6 preflight items; engine now has 7 (datum-z0 added) | Patched expectations to 7 items + acknowledged datum-z0 in test sequence |

---

## UI walk table

| Step | Result | Screenshot | Notes |
| --- | --- | --- | --- |
| G1-A-1 Setup: new job | **PASS** | SHAKE_00_setup_initial.png | Setup active, Material Setup fields visible, recipe card shows 4 options |
| G1-A-2 Recipe selection | **PASS** | SHAKE_01_recipe_selected.png | Decorative Panel recipe selected; job created |
| G1-A-3 Design stage | **PASS** | SHAKE_02_design_signage.png | Design active; ops bar (Weld/Subtract/Intersect/Join/Trim) visible; layers panel present |
| G1-A-4 Cut stage | **PASS** | SHAKE_03_cut_stage.png | Cut active; "Add Toolpath" button; Recalculate Dirty(0); Save Toolpaths; Send to Machine |
| G1-A-5 Preview stage | **PASS** | SHAKE_04_preview_stage.png | Preview active; Wireframe/Heightfield/Combined radio; Simulate; Continue to Machine |
| G1-A-6 Machine: connect sim | **PASS** | SHAKE_05_machine_connected.png | Connected; Simulator selected; preflight checklist 7 items visible; Hold/Resume/Reset visible |
| G1-A-7 Machine: preflight → run | **PASS** | SHAKE_06_preflight_done.png | "I've Verified All Items — Ready to Run" → "Pre-flight passed"; Run Job(11 lines) visible |
| G1-A-8 Machine: stream complete | **PASS** | — | 11/11 ok responses received; sim completed air-cut square |
| G1-A-9 Machine: post-stream state | **PASS (fixed in-loop)** | — | **SPK-UI607** fixed + verified: preflight checklist visible again, big RUN gone, no "Streaming" stuck after 11-line air-cut |
| G1-A overall | **PARTIAL** | — | Decorative Panel recipe produced 0 vectors — Design/Cut walked empty; Machine ran **built-in air-cut (11 lines)**, not a recipe-toolpath handoff. Full chain not proven end-to-end. |
| G1-B Sign/V-Carve | **PASS (AX walk 2026-08-05)** | Signage recipe E2E walked natively via AXPress (see Signage walk table below); CLTs 0601/1106b PASS as engine evidence |
| G1-C Dirty export | **PASS (CLT)** | — | SPK-0603 CLT proves dirty blocks export + expert override |
| G1-D V-Carve open-vector | **PASS (CLT)** | — | SPK-0604 CLT proves open vectors block V-Carve |
| G1-E Stage density + safety | **PASS** | — | 6 stage rail buttons ≤12; Hold/Resume/Reset visible when connected |
| G1-F Model stage | **PASS** | SHAKE_07_model_stage.png | Rough 3D/Finish 3D buttons; empty-state CTA; Studio3D note informational |
| G2 Tutorial walk | **DOCS FIXED** | — | SPK-UI604 [x]; optional G2 UI re-walk |

### UI bugs found

| Card | Priority | Description |
| --- | --- | --- |
| **SPK-UI605** [x] | P2 | **FIXED 2026-08-05 (Cursor):** Import hub only auto-shows when canvas has 0 vectors; ops bar **Import…** opens a sheet when geometry already exists. |
| **SPK-UI602** [x] | P2 | **FIXED 2026-08-05 (Cursor):** Recipe picker is a real sheet (`RecipePickerView`) with Cancel + all `defaultRecipes` incl. Custom; card copy generated from the same list. |
| **SPK-UI607** [x] | P2 | Post-stream state stuck on "RUN" — **FIXED + VERIFIED in-loop 2026-08-05** |
| **SPK-UI603** [x] | P2 | **FIXED 2026-08-05 (Cursor):** Profile create routes through `addToolpathNode` (default tool); summary distinguishes depth vs finish passes; layer-membership guard. |
| **SPK-UI604** [x] | P2 | Tutorial rewritten to match app (Hermes 2026-08-05). |
| **SPK-UI606** [x] | P2 | **FIXED 2026-08-05 (Cursor):** `Window("ShopPilot", id: "main")` + `NSQuitAlwaysKeepsWindows=false`. |
| **SPK-UI608** [x] | P2 | **FIXED 2026-08-05 (Hermes, Signage walk):** Recipe cards `.onTapGesture`-only → not AX/keyboard accessible, Create Job stayed disabled. Added `.accessibilityElement(.combine)` + `.isButton` + `.accessibilityAction` on the card; AXPress-select verified. |

---

## New SPK bug cards filed

1. **SPK-UI605** [x] — Import panel — fixed
2. **SPK-UI602** [x] — Recipe Cancel + Custom — fixed
3. **SPK-UI607** [x] — Post-stream state — fixed
4. **SPK-UI603** [x] — Profile create anomalies — fixed
5. **SPK-UI604** [x] — Tutorial stale — fixed
6. **SPK-UI606** [x] — Double window — fixed

---

## Signage UI walk — P0-B follow-up (2026-08-05, Hermes coder)

**Run:** `.build/debug/ShopPilot` @ `f3eed0a` + SPK-UI608 fix, driven natively with AXPress (System Events) + window capture + vision asserts. Simulator only. Screenshots: `/tmp/shoppilot-signage-walk-20260805/shots/`.

| Step | Result | Screenshot | Notes |
| --- | --- | --- | --- |
| S1 Setup initial | **PASS** | S1_setup_initial.png | Setup active; "Choose a Recipe" card copy = "Portrait Relief • Decorative Panel • Signage • Custom" (generated from `JobRecipe.defaultRecipes` — UI602 copy fix on-screen) |
| S2 Recipe sheet | **PASS** | S2_recipe_sheet.png | Sheet shows all 4 recipes incl. **Custom**, search field, Cancel + Create Job (UI602 sheet fix on-screen) |
| S3 Signage selected | **PASS** | S5_signage_selected.png | Signage card AXPress-selectable after SPK-UI608 a11y fix (blue border + tint); **before fix the cards were `.onTapGesture`-only — invisible to AX/keyboard, Create Job stayed disabled** |
| S4 Job created | **PASS** | S7b_signage_created.png | Design active; "Signage Job" + "Sign Sheet"; layers Text(4)/Border(1); V-Carve 1 (Recipe) node; 5 vectors, 1 toolpath; glyphs visible |
| S5 Design import panel | **PASS** | S7b_signage_created.png | **No "Import Design File" panel on canvas despite 5 vectors present** (UI605 fix on-screen; the 08-05 morning shot SHAKE_02_design_signage.png showed the panel over this exact job) |
| S6 Cut stage | **PASS** | S8b_cut.png | V-Carve 1 (Recipe) node in tree; "All toolpaths up to date" (no dirty badge); G-code preview live; total ~4m 27s |
| S7 Preview stage | **PASS** | S9b_preview.png | Wireframe path visible in-sheet (not blank); stats 403 lines · 1 op · 5 vectors; ~4m 27s (3m 51s cutting) |
| S8 Machine: connect | **PASS** | S11_connected.png | Simulator selected (default); Connect → **Connected** (green); Hold/Resume/Reset visible; jog + Zero X/Y/Z present |
| S9 Machine: load, no auto-run | **PASS** | S11_connected.png | Buffer loaded "403 G-code lines" on connect; **status Idle — zero motion until explicit RUN** |
| S10 Preflight ack | **PASS** | S12_preflight_acked.png | "I've Verified All Items — Ready to Run" → **"Pre-flight passed"** + big green **RUN** armed |
| S11 Machine: run | **PASS** | S13_running.png | RUN → **Streaming 29/394**, progress bar, console "ok" acks flowing |
| S12 Machine: complete + post-stream | **PASS** | S14_complete.png | Stream finished; **preflight checklist returned (items unchecked + "I've Verified All Items" bar), big RUN gone, no stuck "Streaming"** — SPK-UI607 re-verified on the recipe-toolpath handoff (403-line V-Carve, not the 11-line air-cut) |
| Spot-check G1-C dirty export | **CLT-proven, UI trigger blocked** | — | SPK-0603 CLT proves dirty blocks export + expert override. In-app trigger needs a canvas mouse op (select vector → nudge/delete); **CGEvent clicks are TCC-denied for this harness** (AXPress only). No new bug. |
| Spot-check G1-D open-vector V-Carve | **CLT-proven, UI trigger blocked** | — | SPK-0604 CLT proves open vectors block V-Carve. Same harness limitation (needs canvas draw). No new bug. |

### Bug found + fixed in-loop

| Card | Priority | Description |
| --- | --- | --- |
| **SPK-UI608** [x] | P2 | **Recipe cards not accessible** — `RecipeCard` used `.onTapGesture` only (no accessibility element/action, no keyboard path), so AX/keyboard users could never select a recipe and "Create Job" stayed disabled. **FIXED 2026-08-05 (Hermes, in-loop):** `.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)` + label/hint + `.accessibilityAction { selectedRecipe = recipe }` on the card in `recipeGrid`. Verified by the S3 step above (AXPress selects the card; Create Job enabled). |

---

## Cursor follow-up (2026-08-05 afternoon)

| Item | Result |
| --- | --- |
| UI602 / 603 / 605 / 606 code fixes | Build green (`swift build --product ShopPilot`) |
| Signage CLTs | `ShopPilotVerify0601` PASS, `ShopPilotVerify1106b` PASS, `ShopPilotVerifyUI601` PASS |
| Signage native AX walk | **BLOCKED** — Cursor agent lacks Accessibility TCC |
| SPK-0623 | **LEFT [ ]** — owner: one Signage recipe click-through, then decide |

---

## Gaps from SHAKE_MATRIX (SPK-SHAKEa)

| Gap | Status |
| --- | --- |
| G1 — `fixtures/gcode/calibration_square.nc` missing | **CLOSED (SPK-SHAKEb)** — 50mm air-cut calibration square committed; `AppSession.loadFixtureGCodeIfNeeded` now finds it (falls back to built-in air-cut only when absent) |
| G2 — No Calibration recipe | **CLOSED (SPK-SHAKEb, fixture path)** — `fixtures/shoppilot/Calibration.shoppilot` package (200×200×18, 50mm square + real Profile toolpath) covers the driver's G1-A flow; a first-class recipe stays out of scope unless owner wants it |
| G3 — Torture fixtures not fed through importer | **PARTIAL** — SPK-SHAKEd feeds the happy-path fixtures through `SVGImporter` / `DXFParser` / `STLHeightfieldImporter` with exact-geometry asserts + .shoppilot round-trip; the defect-class torture fixtures remain gate-only (`verify_import_torture.py` asserts their classes) |
| G4 — Undo matrix unproven | **CLOSED (SPK-SHAKEe)** — 9 op families walk op → snapshot → restore → identical + redo-contract (same snapshot contract as `AppSession.performUndoRestore`) |
| G5 — Import→save→open→export round-trip | **CLOSED (SPK-SHAKEd)** — SVG/DXF/STL/.shoppilot/G-code matrix, 7 checks PASS |
| G6 — Strategy × dirty × recalc × export-block matrix | **CLOSED (SPK-SHAKEf)** — 6 strategies × markers × only-dirty recalc × export gate, 14 checks PASS |

---

## Deliverables

1. ✅ `docs/planning/SHAKE_MATRIX.md` — 35-row surface inventory
2. ✅ `scripts/run_overnight_shakedown.sh` — harness script + chmod +x
3. ✅ `results/CLTS.md` — 81-row CLT table (78 targets + header + import-torture)
4. ✅ `docs/planning/SHAKE_REPORT_20260805.md` — this report
5. ✅ `MASTER_KANBAN.md` — SHAKE cards split + claimed/closed + Work log
6. ✅ `/tmp/shoppilot-shake-ui-20260805/shots/` — 11 screenshots

---

**SPK-0623 left [ ] — owner decision after reading this report.**
