# ShopPilot — Shakedown Surface Matrix (SPK-SHAKEa)

**Date:** 2026-08-05 · **Author:** Hermes coder (SPK-SHAKEa) · **Source truth:** Package.swift (78 registered ShopPilotVerify* targets), `Sources/ShopPilot/AppSession.swift`, `Sources/ShopPilotCore/MachineSession.swift`, LEAN_CNC_SCOPE.md, UI_ACCEPTANCE_DRIVER.md, MASTER_KANBAN worklog 2026-08-03/04.
**Bar:** Lean P0 surfaces only. Cloud / laser / CRV reverse-eng / App Store / notarize / license / live CNC are **out of scope** (`[-]`).
**Legend:** Entry = how a user reaches the surface (UI / ⌘K / API). Engine = owning types. Persist = `.shoppilot`/params round-trip. Existing Verify = CLT names that must stay green. Gap = honest delta found during inventory. Card = SPK-SHAKE slice that owns closing the gap (or `—` if covered).

| Surface | Entry (UI / ⌘K / API) | Engine | Persist | Existing Verify | Gap | Priority | Card |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Job / document** | | | | | | | |
| Job setup: sheet + material | Setup stage inline form; ⌘K New Job | `Job`, `Sheet`, `Material` (Core), `NewJobView` | `.shoppilot` payload | `1100`, `1132` (72 presets), `0601` (457.2×609.6×19.05 sheet) | Stock-preset picker E2E not UI-walked | P0 | SHAKEh |
| `.shoppilot` save/open | File menu / ⌘K (default-location package I/O) | `AppSession.savePackage/openPackage/applyPackagePayload` | Codable `Job` + payload | `1100`, `1101e/f/g`, `3Da` (Job round-trip), `1136a–d` (legacy decode) | No fixture-pack save/open round-trip per format; no legacy-package fixture | P0 | SHAKEd |
| Undo/redo | ⌘Z / ⇧⌘Z (session snapshot) | `AppSession.undo/redo`, snapshot | snapshot in session only | `1101d`, `1137` (round-trip) | **No CLT proves each design op is undo-restored** (ops → snapshot → undo) | P0 | SHAKEe |
| Dirty tracking | Cut badge + "Recalculate Dirty (N)" | `markDirty/markClean`, `recalculateDirtyToolpaths` | `PersistedToolpath.isDirty` | `0603`, `1102c`, `0319` (follow-source dirty) | Art-edit → dirty is 0319-proven; UI badge walk pending | P0 | SHAKEf |
| **Design** | | | | | | | |
| Draw/edit (rect/circle/line/polyline/freehand, node edit) | DesignCanvasView tools + node-edit toggle | `VectorShape` kernel, `ShapeNodeEditor` (Geometry) | via Job vectors | `1101b` (node edit), `1101j`, `1101k`, `0314a` (selectAll) | Node-edit + undo pairing not CLT-proven | P0 | SHAKEe |
| Selection (click / ⌘ / ⇧) | Canvas gestures → `selectedShapeIndices` | session selection | n/a | `0314a`, `1101d` | Multi-select undo paths not CLT-proven | P0 | SHAKEe |
| Layers CRUD + visibility/lock | Layers panel (eye/lock/reorder/rename) | `AppSession` layer funcs, `LayerVisibility.distribute` | layer order/flags round-trip | `1123`, `1137` (layer-id faithful) | — | P0 | SHAKEe |
| Boolean weld / subtract / intersect | Design Ops bar (≥2 selected) | `ShapeJoinEngine` (Geometry) | undo-point + dirty + `syncLayerVectors` | `0210` (goldens), `1101d` | Per-op undo-restore not CLT-proven | P0 | SHAKEe |
| Join / close / trim | Design Ops bar | `ShapeJoinEngine.trimToBox` + Sutherland–Hodgman | same | `1101d`, `0211` (gap probe) | — | P0 | SHAKEe |
| Transforms: nudge/flip/rotate/scale/offset | Ops bar + ⌘K | `ShapeTransformer`, session `apply*` | undo-point + dirty | `1101f`, `1101FlipH`, `1101h` | — | P0 | SHAKEe |
| **Import / export** | | | | | | | |
| SVG import | Import hub | `SVGImporter` (Geometry) | layer-faithful `addShapes` | `1101e` (parse + viewBox + round-trip) | **Importer behavior vs torture fixtures not CLT-proven** (gate checks fixtures, not import) | P0 | SHAKEd |
| DXF import | Import hub | `DXFParser` (Geometry) | same | `1101g` (LINE/POLY/CIRCLE/ARC + degrees→radians) | same; unit-metadata (`$INSUNITS`) path not CLT-proven | P0 | SHAKEd |
| STL relief import | Model stage / Design → STL Relief | `STLManager` → `HeightfieldData` | `Job.stlHeightfield` (legacy-safe optional) | `3Da` (footprint+apex+legacy), `3Db` | Heightfield persists through save/open — 3Da covers round-trip | P0 | SHAKEd |
| G-code export (GRBL) | Cut → Save Toolpaths… (NSSavePanel) | `GRBLPostProcessor`, `CutToMachineBridge` | via post + profile store | `1102g` (full-tree + golden post), `0415` (units/posts), `1102b` | **Import→save→open→export round-trip matrix missing** | P0 | SHAKEd |
| Dirty export block | Save blocked alert + expert override | `ExportBlocker.validateForExport` | `isDirty` persisted | `0603`, `1102c` | — | P0 | SHAKEf |
| **Fixtures** | | | | | | | |
| Happy-path SVG/DXF/STL + `.shoppilot` packs | fixtures/ | — | — | `verify_import_torture.py` (28 checks, 12 files) | **`fixtures/gcode/calibration_square.nc` referenced at AppSession.swift:1754 but MISSING** (only rapid_only.nc + square_air_10mm.nc exist) | P0 | SHAKEb |
| Calibration + Sign packages | fixtures/ | `SignRecipeManager` (Geometry) | job vcarve fields | `0601` (Sign), `0600` (calibration E2E via fixture) | **No "Calibration" recipe exists in code** (only "Signage"); no packaged `.shoppilot` fixtures | P1 | SHAKEb |
| **Cut strategies** | | | | | | | |
| Profile | Cut add-op + params form | `ProfileToolpathEngine` | `paramsJSON` + `toolID` + `isDirty` | `1102a/c/d`, `1136a`, `Golden25D`, `ProfileToolpath`, `0600` | — | P0 | SHAKEf |
| Pocket | same | `PocketToolpathEngine` (spiral, plunge-fix) | same | `1102d`, `1136b`, `1102h` | — | P0 | SHAKEf |
| Drill (+ peck) | same | `DrillToolpathEngine` (peck guard) | same | `1102d`, `1136c` | — | P0 | SHAKEf |
| V-Carve + clearance pass | same | `VCarveToolpathEngine` + clearance chain | same | `1136d`, `VCarveClear`, `1106a/b`, `Golden25D` | — | P0 | SHAKEf |
| Rough3D / Finish3D (if unlocked) | Model stage buttons | heightfield rough/finish/rest | same | `3Da`, `3Db`, `3DGolden`, `3DRest`, `3DUI` | — | P0 | SHAKEf |
| Recalc / dirty / export gates | "Recalculate Dirty (N)" | `recalculateDirtyToolpaths` (dirty-only) | `isDirty` | `1102c`, `0603`, `0319` | Strategy-matrix × dirty-gate combined CLT missing | P0 | SHAKEf |
| **Preview** | | | | | | | |
| Wireframe + material sim | Preview stage (Combined) | `WireframeRenderer`, `ToolpathSimulator` | n/a | `1103a/c/d`, `1103e` (sheet-aware), `1103` (empty state), `0600/0601` | — | P0 | SHAKEg |
| Draft sim cancel (non-blocking) | Cancel button | background Task cancellation | n/a | `1103b` (via 1103e cancel-immediate/mid-run), `0310a` | — | P0 | SHAKEg |
| **Machine (sim)** | | | | | | | |
| Connect/disconnect | Connect panel (Simulator) | `MachineSession.connect`, `SimulatorTransport` | profile store | `1104`, `1104a`, `0404a`, `0404c`, `FMR013–019` | — | P0 | SHAKEg |
| Load (zero bytes, no auto-run) | Cut→Machine handoff | `loadGCode` | n/a | `1104b` (zero-bytes proven), `0600/0601` | — | P0 | SHAKEg |
| Preflight gate | Preflight list + "I've Verified All Items" | `PreflightGate` | n/a | `1104b`, `FMR016`, `0404a` | — | P0 | SHAKEg |
| Run / stream / progress | Run Job (N lines) | `GCodeStreamer` (throttled) | n/a | `0404c`, `0418` (10k lines), `1104d`, `UI601` (stop-stream deadlock fix) | — | P0 | SHAKEg |
| Hold / Resume / Reset | chrome buttons | `hold/resume/reset` | n/a | `1104d` (hold `!` / resume `~` / complete), `1104` (reset clears alarm) | — | P0 | SHAKEg |
| **Safety chrome** | | | | | | | |
| Hold/Reset always visible while connected | Machine stage fixed chrome | — | — | `1104b/d` (behavior) | Vision assert only — UI walk (G1-E) | P0 | SHAKEh |
| No auto-run on load | — | `loadGCode` zero bytes | — | `1104b`, `0600/0601` | UI walk re-confirm (G1-A step 6) | P0 | SHAKEg/h |
| V-Carve open-vector block | preflight panel + CTA | `VectorPreflight.vCarveGate` | n/a | `0604` (open blocked, closed free) | — | P0 | SHAKEh |
| **Recipes** | | | | | | | |
| Sign recipe (text→curves→V-Carve) | "Choose a Recipe" card | `SignRecipeManager` (Geometry) | `Job.vcarveGCode/paramsJSON/time` | `0601`, `1106a`, `1106b` (full chain) | "Custom" listed in card copy but not in sheet (SPK-UI602, P2, open) | P1 | SHAKEh |
| Calibration recipe | — | — | — | `0600` (E2E via fixture) | **No Calibration recipe; fixture missing** (see Fixtures rows) | P1 | SHAKEb |
| **Open UI cards (2026-08-04 walk)** | | | | | | | |
| SPK-UI602 recipe sheet copy/Cancel | Select Recipe sheet | — | — | — | Card copy lists Custom; sheet lacks it + no Cancel affordance | P2 | SHAKEh (fix if quick) |
| SPK-UI603 profile-creation anomalies | Cut add Profile | — | — | — | layer reassignment + "No tool" with computed lines + pass-count mismatch | P2 | SHAKEh (fix if quick) |
| SPK-UI604 tutorial stale ×4 | docs | — | — | — | Text tool / ⌘T / Load File / ⌘N mismatch | P2 | SHAKEh (fix if quick) |
| SPK-UI605 import panel re-show + empty picker | Import hub | — | — | — | panel re-shows every Design entry; empty fileImporter sheet | P2 | SHAKEh (fix if quick) |
| SPK-UI606 double window on launch | App entry | — | — | — | restored frame + new default window | P2 | SHAKEh (fix if quick) |

## Honest gap summary (drives SPK-SHAKEb…g)

1. **G1 — Missing fixture:** `AppSession.swift:1754` loads `fixtures/gcode/calibration_square.nc`; the file does not exist (only `rapid_only.nc`, `square_air_10mm.nc`). Load path would fail / degrade silently. → SPK-SHAKEb creates air-cut-safe fixture + wires gate.
2. **G2 — No Calibration recipe:** only `SignRecipeManager.createSignJob` ("Signage") exists; the UI driver's G1-A "Calibration recipe" step had to substitute Signage on 08-04. → SPK-SHAKEb adds packaged Calibration `.shoppilot` fixture (recipe itself stays out of scope unless owner wants it).
3. **G3 — Torture fixtures are gate-only:** `verify_import_torture.py` asserts fixture defect classes, not importer behavior. → SPK-SHAKEd CLT feeds fixtures through `SVGImporter`/`DXFParser` and asserts tolerant outcomes.
4. **G4 — Undo matrix unproven:** no CLT walks op → snapshot → undo → state-restored for boolean/transform/layer ops. → SPK-SHAKEe.
5. **G5 — Round-trip matrix missing:** no single CLT does import → save → open → export per format. → SPK-SHAKEd.
6. **G6 — Combined gates:** strategy × dirty × recalc × export-block not matrixed in one CLT. → SPK-SHAKEf.
7. **G7 — UI walk deltas:** SPK-UI602…606 open from 08-04; SHAKEh re-walks and fixes quick P2s in-loop.

## Verify-name integrity check (SPK-SHAKEa AC)

All 78 `ShopPilotVerify*` names listed above resolve as `.executableTarget` entries in `Package.swift` (checked 2026-08-05: grep dirs vs registrations → 0 unregistered).
