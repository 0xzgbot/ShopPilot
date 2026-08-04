# ShopPilot — Ship Checklist

**Last reviewed:** 2026-08-04
**Roadmap:** [`docs/planning/FINISH_ROADMAP.md`](docs/planning/FINISH_ROADMAP.md)
**Board:** [`MASTER_KANBAN.md`](MASTER_KANBAN.md)
**Installer build plan:** [`docs/planning/INSTALLER_BUILD_PLAN.md`](docs/planning/INSTALLER_BUILD_PLAN.md)

Do **not** sign v1.0 until Finish Tracks 1–5 are complete (SPK-0623).

## DoD reminder

Each feature needs **Engine + UI + Persist + Verify**. Build-only does not count.

## Track exits (updated 2026-08-04 — honest walk, Hermes coder)

| Track | Focus | Gate card | Status |
| --- | --- | --- | --- |
| 1 | Document spine (save/open round-trip, inspector bind, ⌘K routing) | SPK-1100 | [x] — spine + round-trip + inspector verified; ⌘K routing live |
| 2 | Design editor product (canvas, node edit, measure, layers, import) | SPK-1101 | [x] — canvas select/move + layers + SVG import + node edit/measure live (1101a–g verifies) |
| 3 | Toolpaths + preview + sign | SPK-1102, 1103, 1106 | [x] — all four strategies + dirty/export gate (0603) + preflight V-Carve gate (0604) + 3D rough/finish + goldens + sign E2E (1106a/b) verified |
| 4 | Machine handoff | SPK-1104 | [x] — session→buffer load verified; stream/hold/reset live; post auto-select from profile (0415) |
| 5 | v1 gate / XCTest / docs | SPK-1105, SPK-0623 | [x] XCTest 429/429 green via test.sh (Xcode-aware toolchain); goldens via ShopPilotVerify* targets — **SPK-0623 itself still `[ ]`: requires human gates below** |
| 6 | Phases H–K | after SPK-0623 | blocked |

## Installer-verified data (shipped 2026-08-03/04, per INSTALLER_BUILD_PLAN)

- [x] 72 stock sheet presets (SPK-1132) — Job Setup picker, persisted, golden-verified
- [x] Parity matrix §R — 19 new rows + verified form-field annotations (Profile/Pocket/V-Carve/Drill)
- [x] Tool DB seed 13 classes / 17 defaults + 3-part linkage (SPK-1133 + SPK-1133b, P1) — `ShopPilotVerify1133b` PASS
- [x] Post auto-select from machine profile — GRBL/Universal + G21/G20 units (SPK-0415, P1) — `ShopPilotVerify0415` PASS
- [ ] Post engine v2 template grammar + rotary wrap (SPK-1134, P1) — **deferred**: in/mm covered by SPK-0415; rotary wrap not a real workflow blocker
- [ ] HTML job sheet → PDF (SPK-1135, P1) — deferred unless blocking a real user workflow
- [x] P0 form-field parity (SPK-1136, P0) — 1136a–d verifies PASS

## Human blockers `[!]` (unmet — SPK-0623 stays `[ ]` until these pass)

- SPK-0010 interviews (optional v1)
- SPK-0419 live air-cut
- SPK-0614 license
- SPK-0615 Apple Developer credentials
- SPK-0621 notarization (deps 0615)
- SPK-1009 App Store (post-v1)
- **G1 human QA**: screen captures of calibration/sign E2E with 0.1mm tolerance sign-off (CLTs pass; the human capture + signature are not done)
- **G2 tutorial walkthrough**: new-user first-cut within 15 minutes — needs a human to attempt it
- **G3 release run**: `scripts/build.sh --release` + full notarization flow + signed DMG + SHA-256 published — needs Apple credentials

## Sign-off (v1.0)

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Engineer | — | — | Pending SPK-0623 human gates |
| QA | — | — | Pending SPK-1105 + goldens + G1 captures |
