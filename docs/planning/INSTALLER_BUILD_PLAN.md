# ShopPilot — Installer-Verified Build Plan

**Date:** 2026-08-03
**Supersedes:** nothing — sits alongside `FINISH_ROADMAP.md` (order of tracks unchanged) and `PRODUCT_VISION_PLAN.md` (vision unchanged).
**Provenance:** reference trial installer (V12.5.1.0 Build 12738) unpacked + 4 analysis passes → `/tmp/installer_reports/01–04_*.md`, distilled in `INSTALLER_BREAKDOWN.md`, evidence rows in `FEATURE_PARITY_MATRIX.md` §R.
**One-line change:** We now have **installer-verified ground truth** for the P0 toolpath forms, the post-processor ecosystem (964 posts incl. GRBL), the tool database, and the data a professional-grade app ships — so the next build steps ship *data + form parity* instead of more engine stubs.

---

## 1. What the research changes (findings → build impact)

| # | Installer finding | Build impact | Track |
|---|---|---|---|
| 1 | Profile form = 7 pages (`uiProfileMachineForm`: tabs/ramping/leads/corners/sequence/startpoint/advanced) with exact param keys (`CutDepth/PassDepth`, `ProfileType ON/OUTSIDE/INSIDE`, `CutDirection`, `TabLength/TabThickness/TabDistance`, 5 ramp enums, lead arc/line) | **SPK-1136**: P0 strategy forms must expose this surface. Matrix §R2 is the AC. | Track 3 |
| 2 | Pocket = offset/raster + `RasterAngle/RasterOptimizer/DoRasterClearance/ClearStepover/UseAreaClearTool` + multi-tool pocket form; V-Carve = `DoEngraving/EngravingStepover/FlatDepth/MaxDepth/OvercutDistance`; Drill = peck/dwell/retract/`ToolNumber` + helical ramps | Same as #1 — form field parity for all four P0 strategies | Track 3 |
| 3 | Post ecosystem: **964 posts in SQLite ppdb**; GRBL in/mm, Grbl WrapY2A (rotary), Shapeoko, Easel-Grbl, Avid, X-Carve Pro, Openbuilds, LinuxCNC, Mach2/3, Centroid, Masso, Duet; `.pp` grammar = `POST_NAME`/`UNITS`/`LINE_ENDING` + `VAR X_POSITION = [X\|C\|X\|1.3]` format specifiers | **SPK-1134**: post engine v2 as a **template grammar** (mirror the format-specifier model, write our own) — one engine, N posts. GRBL in/mm + rotary-wrap are the first two templates. | Track 3 |
| 4 | Tool DB: 13 classes (`mc*Tool`), 17 default tool assignments (Profile→End Mill ¼", V-Carve→V-Bit 90° 1¼", QuickEngrave→Diamond Drag…), 3-part linkage `db_geom_id`/`db_cut_data_id`/`db_mach_cut_data_id`, per-machine cutting data | **SPK-1133**: seed tool DB with real defaults; model geometry/cut-data/machine-cut-data split so switching machines doesn't re-enter speeds/feeds | Track 3 |
| 5 | **72 stock sheet presets** (6 imperial × 6 thickness, 6 metric × 6 thickness) shipped as `.crvt3d` templates | **SPK-1132**: ship the same preset set as data + Job Setup picker (our own format, same dimensions) | Track 1–2 boundary |
| 6 | Job sheet = **HTML template** (`PrintSheetTemplate.html`, A4 CSS) rendered per toolpath | **SPK-1135**: HTML job-sheet template rendered to PDF via WebKit — replaces PDF-only approach | Track 3 |
| 7 | The reference has **no machine-control UI at all** (control = posts + machine DB); machine capability flags (`SupportsDwell/Spindle/Toolchange`) gate form options | Confirms Track 4 machine control is our differentiator. Add capability flags to `ToolDatabase`/machine profile models. | Track 4 |
| 8 | V12.5 verified: Keep-Out Zones (non-rotary, tiling-incompatible, violation blocks calc), Sketch Carving, Laser Sketch Engraving, Fluting, Inlay wizards, Wrapping, Double-sided | Keep-outs v0 (SPK-0308) is ship-critical; everything else stays post-v1 with verified AC | Track 3 / post-v1 |
| 9 | Trial limits: export disabled, laser gated, content remote-fed | No impact on build; informs Windows live-capture expectations | — |
| 10 | Import list verified: dxf/dwg/eps/ai/pdf/svg/stl/3dm/skp/3dClip/v3m/v3d/pvc + bitmaps; export DXF/SVG/STL/grayscale/PDF | Locks K-section AC; SVG/DXF import stay P0; 3dm/skp stay P2 | Track 2 |

## 2. Sequencing (unchanged tracks, new cards interleaved)

```text
Track 1 spine [1100 ✓] → Track 2 Design [1101…] → Track 3 Toolpaths/Preview [1102, 1103 + 1132–1136]
                                                      ↘ Track 4 Machine [1104…] (∥ after Track 1)
Track 5 v1 gate → Track 6 H–K (post-v1)
```

**Priority rule change:** within Track 3, finish **SPK-1132 (presets)** and **SPK-1136 (form parity)** before or with SPK-1102 close — they are the data + AC the Cut stage product needs. SPK-1133/1134/1135 are P1 follow-ons, not gates.

## 3. New cards (added to MASTER_KANBAN.md, all `// P0/P1`, Track 3 unless noted)

| Card | Title | Pri | AC (Definition of Done) | Deps |
|---|---|---|---|---|
| SPK-1132 | Stock sheet presets — 72 presets as data + Job Setup picker | P0 | Engine: preset table (6 imperial × 6 thickness, 6 metric × 6 thickness: 2'×2'…8'×4' × ⅛″–1″; 610×610…2438×1219mm × 3–25mm); UI: Job Setup lists presets, one-click material sheet; Persist: preset selection saves in `.shoppilot`; Verify: golden test that all 72 presets exist and produce correct sheet dims | SPK-1100 |
| SPK-1136 | P0 strategy form-field parity (Profile/Pocket/V-Carve/Drill) | P0 | Engine: param models cover the installer-verified keys (§R2 of matrix); UI: each form exposes the verified surface (Profile 7 pages incl. tabs/ramps/leads/corners/order; Pocket offset/raster + clearance pass; V-Carve engraving/flat-depth/overcut; Drill peck/dwell/retract/helical); Persist: all params round-trip; Verify: form-field checklist test (one test per strategy asserting every §R2 key is present in the model) | SPK-1102 |
| SPK-1133 | Tool DB seed + 3-part linkage model | P1 | Engine: 13 tool classes (`mc*Tool` taxonomy as our own `ToolClass`), 17 seeded defaults (Profile→End Mill ¼", V-Carve→V-Bit 90° 1¼", QuickEngrave→Diamond Drag 90°, LaserEngrave→3.8W 0.3mm…); geometry/cut-data/machine-cut-data split with per-machine cutting data; UI: tool editor groups by class; Persist: vtdb-equivalent JSON schema (our own); Verify: golden test — seeding yields expected default per strategy | SPK-0301 |
| SPK-1134 | Post engine v2 — template grammar + GRBL in/mm + rotary wrap | P1 | Engine: template-based post where format specifiers (`[X\|C\|X\|1.3]`-style: prefix/justify/char/decimals) are our own grammar; two shipped templates: GRBL in/mm, GRBL rotary wrap (Y2A); UI: post picker in Save Toolpaths; Persist: templates as bundled resources; Verify: golden G-code for each template matches hand-written reference | SPK-0313 |
| SPK-1135 | HTML job sheet → PDF | P1 | Engine: HTML template (A4) filled from toolpath/session data; UI: print/export sheet from Output; Persist: template bundled; Verify: golden — rendered PDF contains toolpath name, tool, feeds/speeds, dims, time estimate | SPK-0508 |

## 4. Upgraded AC for existing cards (evidence reference)

| Card | Upgrade |
|---|---|
| SPK-1102 Cut stage | Profile/Pocket/V-Carve/Drill forms meet **SPK-1136** parity (matrix §R2). Export block covers dirty + keep-out violation (verified behavior: calc blocks on keep-out violation). GRBL post from tree uses **SPK-1134** engine. |
| SPK-0301 Tool DB | Seed per **SPK-1133**; tool classes named after our own taxonomy but matching the 13-class surface (end mill, radiused end mill, ball nose, V-bit, engraving, radiused engraving, drill, diamond drag, laser, thread mill, multi thread mill, plasma, form). |
| SPK-0302/0303/0304 | Engines must accept the §R2 parameter sets (e.g. Profile `GeometryDepthOffset`, `Use3dTabs`, `Merge`; Pocket `RasterOptimizer`). G-code output must be GRBL-valid (verified: GRBL post exists in the reference's own DB → it's the hobby default). |
| SPK-0313 GRBL post | Use **SPK-1134** template engine; add rotary-wrap variant (Grbl WrapY2A is a real reference post — wrap X or Y axis, A-axis output). |
| SPK-0508 Job sheet | HTML template per **SPK-1135** (the reference's own is HTML; we mirror the *pattern*, not the file). |
| SPK-0308 Keep-out zones | Verified semantics: zones create from selection, carry clearance, toolpath calc **fails** on violation, non-rotary only, tiling-incompatible. Matches existing KeepOutZones.swift design — keep, productize. |
| SPK-0300 Material setup | Add material→tool cutting-data linkage when SPK-1133 lands ("a machine and a material are required" is the reference's rule for cutting data). |

## 5. Data-first deliverables (spec from reports)

- **Presets (SPK-1132):** exactly 72 — the six imperial sheets and six metric sheets with six thicknesses each (full list in `/tmp/installer_reports/03_assets.md` §2 / breakdown §3). Our own JSON asset, same dimensions.
- **Default tools (SPK-1133):** the 17 assignment table (`/tmp/installer_reports/01_toolpaths.md` §1) — strategy → tool class → canonical default (e.g. `VCarve → mcVBitTool → V-Bit (90°, 1¼")`). These are industry-typical defaults, not third-party IP.
- **Post grammar (SPK-1134):** own format modeled on the observed pattern: identity header (`POST_NAME`/`FILE_EXTENSION`/`UNITS`), line-ending + block numbering options, per-variable format specifiers (prefix/alignment/text/decimals), tool-change + spindle blocks, optional A-axis for rotary. Two templates ship in v1.
- **Job sheet (SPK-1135):** own A4 HTML template with CSS vars; content = job dims, per-toolpath: name, tool, feed/plunge/speed, depth, time estimate (from SPK-0312), total.

## 6. Verification strategy

1. **Form-field checklist tests** (SPK-1136): one XCTest per P0 strategy asserting the full §R2 key set exists in the parameter model — prevents silent AC drift.
2. **Golden G-code** (SPK-1134): hand-written reference G-code for a small sign job per template; engine output normalized (whitespace/rounding) and diffed (existing `GoldenFixtures` pattern, SPK-0317).
3. **Preset golden** (SPK-1132): all 72 presets decode to expected dims; save/open round-trip preserves preset id.
4. **Tool DB golden** (SPK-1133): seeding yields the 17 expected defaults; switching machine swaps `db_mach_cut_data_id` values without touching geometry.
5. `swift build` after every card; XCTest suite per SPK-1105 when toolchain available.

## 7. Explicitly deferred (post-v1, verified-but-not-now)

964-post catalog (we ship 2), 51 preview textures (we ship procedural/CC), cabinet import (KCD/Mozaik…), drill banks, toolpath dicer, toolpath groups, rest machining, laser family, thread milling, photo V-carve, plasma, Sketch Carving, 3D sculpt/sweep, tiling, nesting, Post Studio, machine config packages, tool DB online backup.

## 8. Execution order (next sessions)

1. **SPK-1132** (presets — data asset, quick win, unblocks Job Setup product) — direct write.
2. **SPK-1101 spine remaining** → **SPK-1102** Cut stage with **SPK-1136** form parity riding along.
3. **SPK-1133** (tool DB seed) then **SPK-1134** (post grammar) then **SPK-1135** (job sheet) — P1, in order.
4. Track 4 machine (∥) with capability flags added to tool/machine models.
5. Track 5 gate — XCTest + goldens green.

---

*Companion docs: `INSTALLER_BREAKDOWN.md` (the 9-item basic feature set), `FEATURE_PARITY_MATRIX.md` §R (evidence), `WINDOWS_EXPLORER_PROMPT.md` (live capture, pending).*
