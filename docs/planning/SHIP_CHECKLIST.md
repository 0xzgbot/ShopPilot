# ShopPilot v1.0 — Ship Checklist

**Date:** 2026-07-28  
**Purpose:** All items must be verified and signed off before SPK-0623 is marked `[x]` and v1.0 ships.

---

## G1 — Functional Acceptance

### Calibration Job E2E
- [ ] Create calibration job from recipe (Setup stage)
- [ ] Draw calibration vectors in Design stage
- [ ] Generate Profile toolpath for calibration vectors
- [ ] Run material simulation in Preview stage — verify visual output matches expected cut pattern
- [ ] Connect to SimulatorTransport and stream calibration G-code
- [ ] Verify simulator reports successful completion with correct final dimensions
- **Verification:** Record a screen capture of the full E2E flow. Dimensions must match design within 0.1mm tolerance.
- **Sign-off:** _________________ Date: _______

### Sign Job E2E
- [ ] Create sign job from recipe (Setup stage)
- [ ] Add text vector in Design stage, convert to curves
- [ ] Generate V-Carve toolpath for text
- [ ] Run material simulation — verify engraving depth matches settings
- [ ] Stream to simulator and verify completion
- **Verification:** Screen capture of full flow. Text must be legible after simulation.
- **Sign-off:** _________________ Date: _______

### Unit Tests Green in CI
- [ ] `swift test` passes with 0 failures
- [ ] Geometry tests (offset, boolean) cover all edge cases from SPK-0210
- [ ] Status parser tests cover all GRBL response formats from SPK-0403
- [ ] G-code streamer tests cover ok-wait flow and hold/resume/reset from SPK-0404
- **Verification:** CI script output shows all tests passing. No warnings treated as errors.
- **Sign-off:** _________________ Date: _______

### Dirty Toolpath Export Blocked
- [ ] Create a toolpath, then modify the source vectors
- [ ] Attempt to export G-code — verify it is blocked with dirty flag warning
- [ ] Click "Recalculate" and verify toolpath updates
- [ ] Verify expert override dialog appears when clicking "Export anyway"
- **Verification:** Manual test with screen capture. Export must be blocked by default.
- **Sign-off:** _________________ Date: _______

### Preflight Blocks V-Carve on Open Vectors
- [ ] Create an open vector (gap in path)
- [ ] Attempt to generate V-Carve toolpath — verify it is blocked with plain-English error
- [ ] Verify fix CTA appears ("Auto-close gaps")
- [ ] Apply auto-fix and verify toolpath generates successfully after fix
- **Verification:** Manual test. Error message must be in plain English, not technical jargon.
- **Sign-off:** _________________ Date: _______

### Stage Density Audit (≤12 Icons)
- [ ] Count primary icons in each stage rail position
- [ ] Verify no stage exceeds 12 primary icons
- [ ] Verify secondary/advanced tools are hidden behind disclosure groups or context menus
- **Verification:** Screenshot of each stage with icon count annotated.
- **Sign-off:** _________________ Date: _______

### Hold/Reset Visible When Connected
- [ ] Connect to SimulatorTransport — verify Hold and Reset buttons appear in toolbar
- [ ] Verify Hold button stops streaming immediately
- [ ] Verify Resume button continues from hold point
- [ ] Verify Reset button aborts current job and returns to idle state
- **Verification:** Manual test with screen capture. Buttons must be visible at all times when machine is connected.
- **Sign-off:** _________________ Date: _______

---

## G2 — Docs & Legal

### End-User Tutorial Complete
- [ ] TUTORIAL_FIRST_CUT.md exists and covers all 8 steps
- [ ] Tutorial can be followed by a new user without assistance
- **Verification:** Have someone unfamiliar with ShopPilot follow the tutorial. They should reach "first cut" within 15 minutes.
- **Sign-off:** _________________ Date: _______

### SAFETY.md Complete + In-App Disclaimer
- [ ] SAFETY.md covers all critical safety areas (material verification, simulator-first testing, no Vectric assets)
- [ ] In-app disclaimer displays on first launch
- [ ] Disclaimer includes: verify toolpaths, simulator-first testing, user assumes risk
- **Verification:** Read through SAFETY.md. Launch app and confirm disclaimer appears.
- **Sign-off:** _________________ Date: _______

### Keyboard Shortcuts Documented
- [ ] KEYBOARD_SHORTCUTS.md exists with all shortcuts listed
- [ ] Shortcuts follow Apple HIG conventions (⌘ for commands, ⇧ for modifiers)
- **Verification:** Cross-reference doc against actual implemented shortcuts.
- **Sign-off:** _________________ Date: _______

---

## G3 — Release Engineering

### Versioning Scheme Defined
- [ ] VERSIONING.md exists with semantic versioning rules
- [ ] CHANGELOG.md follows Keep a Changelog format
- [ ] Initial changelog entries cover all v1.0 features from Phase A–G
- **Verification:** Review both documents for completeness and consistency.
- **Sign-off:** _________________ Date: _______

### Distribution Pipeline Ready
- [ ] DISTRIBUTION.md exists with signing, notarization, and distribution steps
- [ ] Build scripts (scripts/build.sh, scripts/test.sh) work end-to-end
- [ ] DMG can be built, signed, and notarized following the documented process
- **Verification:** Run `scripts/build.sh --release` and complete the full notarization flow.
- **Sign-off:** _________________ Date: _______

### GitHub Release Prepared
- [ ] v1.0 tag created on main branch
- [ ] GitHub Release draft includes changelog from CHANGELOG.md
- [ ] Signed .dmg attached as release asset
- [ ] SHA-256 checksum published alongside download link
- **Verification:** Verify the release page renders correctly and assets are downloadable.
- **Sign-off:** _________________ Date: _______

---

## Final Gate

- [ ] All Phase A–G kanban cards marked `[x]` in MASTER_KANBAN.md
- [ ] No open P0 bugs remaining
- [ ] Product manager sign-off: "This is ready to ship"
- [ ] Engineering lead sign-off: "Code is stable, tests pass, no known regressions"

**Ship decision:** _________________ Date: _______  
**v1.0 release date:** _________________
