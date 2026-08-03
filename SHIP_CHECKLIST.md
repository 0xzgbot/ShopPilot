# ShopPilot — Ship Checklist

**Last reviewed:** 2026-08-03
**Roadmap:** [`docs/planning/FINISH_ROADMAP.md`](docs/planning/FINISH_ROADMAP.md)
**Board:** [`MASTER_KANBAN.md`](MASTER_KANBAN.md)
**Installer build plan:** [`docs/planning/INSTALLER_BUILD_PLAN.md`](docs/planning/INSTALLER_BUILD_PLAN.md)

Do **not** sign v1.0 until Finish Tracks 1–5 are complete (SPK-0623).

## DoD reminder

Each feature needs **Engine + UI + Persist + Verify**. Build-only does not count.

## Track exits (updated 2026-08-03)

| Track | Focus | Gate card | Status |
| --- | --- | --- | --- |
| 1 | Document spine (save/open round-trip, inspector bind, ⌘K routing) | SPK-1100 | [~] — spine + round-trip + inspector verified; ⌘K routing being finished (wave) |
| 2 | Design editor product (canvas, node edit, measure, layers, import) | SPK-1101 | [~] — canvas select/move + layers + SVG import live; node edit + measure in wave |
| 3 | Toolpaths + preview + sign | SPK-1102, 1103, 1106 | [~] — profile→G-code wired; presets (SPK-1132) shipped; save flow + export block + preview highlight in wave |
| 4 | Machine handoff | SPK-1104 | [~] — session→buffer load verified; stream/hold/reset live in MachineConnection |
| 5 | v1 gate / XCTest / docs | SPK-1105, SPK-0623 | [ ] — XCTest gated on Xcode toolchain (CLI-only env); goldens via ShopPilotVerify* targets |
| 6 | Phases H–K | after SPK-0623 | blocked |

## Installer-verified data (shipped 2026-08-03, per INSTALLER_BUILD_PLAN)

- [x] 72 stock sheet presets (SPK-1132) — Job Setup picker, persisted, golden-verified
- [x] Parity matrix §R — 19 new rows + verified form-field annotations (Profile/Pocket/V-Carve/Drill)
- [ ] Tool DB seed 13 classes / 17 defaults + 3-part linkage (SPK-1133, P1)
- [ ] Post engine v2 template grammar + GRBL in/mm + rotary wrap (SPK-1134, P1)
- [ ] HTML job sheet → PDF (SPK-1135, P1)
- [ ] P0 form-field parity (SPK-1136, P0 — rides with Cut stage close)

## Human blockers `[!]`

- SPK-0010 interviews (optional v1)
- SPK-0419 live air-cut
- SPK-0614 license
- SPK-0615 Apple Developer credentials
- SPK-0621 notarization (deps 0615)
- SPK-1009 App Store (post-v1)

## Sign-off (v1.0)

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Engineer | — | — | Pending SPK-0623 |
| QA | — | — | Pending SPK-1105 + goldens |
