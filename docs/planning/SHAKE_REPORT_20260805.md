# ShopPilot Shakedown Report — 2026-08-05

**Conductor:** Hermes coder (SPK-SHAKEa…i, overnight shakedown)  
**App:** `.build/debug/ShopPilot` @ `998a7ee` (master, clean)  
**Transport:** Simulator only. **No live CNC / no notarize / no App Store.**  
**Run dir:** `/tmp/shoppilot-shake-ui-20260805/shots/`

---

## Verdict summary

| Area | Result | Notes |
| --- | --- | --- |
| CLT sweep (78 ShopPilotVerify*) | **PASS** | 78/78 PASS, 0 FAIL, 0 WARN. One fix: 1104c CLT stale (6→7 preflight items). |
| Import-torture fixtures | **PASS** | 28/28 checks PASS. |
| G1-A Setup → Design → Cut → Preview → Machine | **PARTIAL** | Decorative Panel recipe produced 0 vectors; Machine ran built-in air-cut (11 lines), not recipe handoff. Post-stream state bug (SPK-UI607) found + fixed in-loop. |
| G1-B Sign → V-Carve | **PARTIAL** | Signage recipe exists but was NOT walked (Decorative Panel substituted). V-Carve covered by CLTs only. |
| G1-C Dirty export gate | **PASS (CLT-proven)** | SPK-0603 CLT proves dirty blocks export + expert override. No in-app trigger (no dirty toolpaths). |
| G1-D V-Carve open-vector block | **PASS (CLT-proven)** | SPK-0604 CLT proves open vectors block V-Carve. No in-app trigger (no open vectors). |
| G1-E Stage density + safety chrome | **PASS** | 6 stage rail buttons ≤12 per stage; Hold/Resume/Reset visible when connected. |
| G1-F Model stage | **PASS** | Rough 3D / Finish 3D buttons present; empty-state CTA; Studio3D note informational. |
| G2 Tutorial walk | **BLOCKED** | No design vectors in Decorative Panel recipe — tutorial steps requiring drawing/text can't be walked. |
| **SPK-0623** | **LEFT [ ]** | **Owner decision after reading this report.** |

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
| G1-B Sign/V-Carve | **PARTIAL** | — | No Sign recipe job walked. **Signage recipe exists in the Select Recipe sheet and was NOT walked** (Decorative Panel was substituted). V-Carve toolpath creation not driven in UI; covered by CLTs only (1106b, VCarveClear, Golden25D). |
| G1-C Dirty export | **PASS (CLT)** | — | SPK-0603 CLT proves dirty blocks export + expert override |
| G1-D V-Carve open-vector | **PASS (CLT)** | — | SPK-0604 CLT proves open vectors block V-Carve |
| G1-E Stage density + safety | **PASS** | — | 6 stage rail buttons ≤12; Hold/Resume/Reset visible when connected |
| G1-F Model stage | **PASS** | SHAKE_07_model_stage.png | Rough 3D/Finish 3D buttons; empty-state CTA; Studio3D note informational |
| G2 Tutorial walk | **BLOCKED** | — | No design vectors in Decorative Panel recipe — tutorial steps requiring drawing/text can't be walked |

### UI bugs found

| Card | Priority | Description |
| --- | --- | --- |
| **SPK-UI605** [~] | P2 | "Import Design File" panel re-shows on every Design entry (even with vectors present); Choose File presented as empty 470×80 fileImporter placeholder |
| **SPK-UI602** [~] | P2 | Recipe sheet lists "Custom" in card copy but sheet has no Custom option; sheet has no Cancel/close (dismiss only by picking or File→New Job) |
| **SPK-UI607** [x] | P2 | Post-stream state stuck on "RUN" — **FIXED + VERIFIED in-loop 2026-08-05**: all stream completion paths now reset `preflightPassed` via `MainActor.run`; preflight checklist returns after run/error/stop |
| **SPK-UI603** [~] | P2 | Profile toolpath creation anomalies (from 08-04 walk): layer reassignment, "No tool" with computed lines, pass-count mismatch |
| **SPK-UI604** [~] | P2 | TUTORIAL_FIRST_CUT.md stale vs app (from 08-04 walk): Text tool / ⌘T / Load File / ⌘N mismatch |
| **SPK-UI606** [~] | P2 | Launch opens two windows after prior force-kill (not reproduced on clean launch) |

---

## New SPK bug cards filed

1. **SPK-UI605** [ ] P2 — Import Design File panel re-shows + empty file picker
2. **SPK-UI602** [ ] P2 — Recipe sheet: no Custom option, no Cancel/close
3. **SPK-UI607** [x] P2 — Post-stream state stuck on "RUN" — **FIXED + VERIFIED in-loop** (preflight reset via MainActor.run on all completion paths)
4. **SPK-UI603** [ ] P2 — Profile toolpath creation anomalies (from 08-04)
5. **SPK-UI604** [ ] P2 — Tutorial stale vs app (from 08-04)
6. **SPK-UI606** [ ] P2 — Double window on launch (from 08-04)

---

## Gaps from SHAKE_MATRIX (SPK-SHAKEa)

| Gap | Status |
| --- | --- |
| G1 — `fixtures/gcode/calibration_square.nc` missing | **OPEN** — AppSession.swift:1754 references it; only rapid_only.nc + square_air_10mm.nc exist |
| G2 — No Calibration recipe | **OPEN** — Only SignRecipeManager (Signage) exists |
| G3 — Torture fixtures not fed through importer | **OPEN** — verify_import_torture.py asserts fixture classes, not import behavior |
| G4 — Undo matrix unproven | **OPEN** — No CLT walks op → snapshot → undo → restored |
| G5 — Import→save→open→export round-trip | **OPEN** — No single CLT does format-family round-trip |
| G6 — Strategy × dirty × recalc × export-block matrix | **OPEN** — Combined gate CLT missing |

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
