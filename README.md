# ShopPilot

Native **macOS** CNC suite: **Aspire-class design + toolpaths + preview**, plus **integrated machine control** for CNC routers (GRBL / FluidNC-class).

> **⚠️ Scope disclaimer:** ShopPilot is a **relief CAM toolpath generator and machine controller**. It is NOT a full solid CAD system — it does not replace Fusion 360, SolidWorks, Rhino, or FreeCAD. Input formats are STL/OBJ mesh files produced by other 3D modeling software. For parametric design from scratch, use a proper CAD tool first, then export STL/OBJ for ShopPilot. See [`docs/planning/PRODUCT_BOUNDARIES.md`](docs/planning/PRODUCT_BOUNDARIES.md) for full scope details.

> **Safety:** Software controls are **not** a substitute for a hardware emergency stop.
> **Research source:** [Vectric Aspire V12 User Guide](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/) (capability parity — independent implementation).

## For humans

| Item | Location |
| --- | --- |
| **Master kanban (single source of truth)** | [`MASTER_KANBAN.md`](MASTER_KANBAN.md) |
| Agent operating manual | [`AGENTS.md`](AGENTS.md) |
| Product plan | [`docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md`](docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md) |
| Feature parity matrix | [`docs/planning/FEATURE_PARITY_MATRIX.md`](docs/planning/FEATURE_PARITY_MATRIX.md) |
| **Safety + in-app disclaimer** | [`docs/planning/SAFETY.md`](docs/planning/SAFETY.md) |
| **Product scope & boundaries** | [`docs/planning/PRODUCT_BOUNDARIES.md`](docs/planning/PRODUCT_BOUNDARIES.md) |
| **Honest scope statement** | [`docs/planning/SHOPPILOT_SCOPE.md`](docs/planning/SHOPPILOT_SCOPE.md) |
| **First-cut tutorial** | [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md) |
| Keyboard shortcuts | [`docs/planning/KEYBOARD_SHORTCUTS.md`](docs/planning/KEYBOARD_SHORTCUTS.md) |
| Distribution + notarization | [`docs/planning/DISTRIBUTION.md`](docs/planning/DISTRIBUTION.md) |
| Packaging tiers | [`docs/planning/PACKAGING.md`](docs/planning/PACKAGING.md) |
| UX stage system | [`docs/planning/UX_STAGE_SYSTEM.md`](docs/planning/UX_STAGE_SYSTEM.md) |
| Release + versioning + changelog | [`docs/planning/VERSIONING.md`](docs/planning/VERSIONING.md), [`docs/planning/CHANGELOG.md`](docs/planning/CHANGELOG.md) |
| CI release workflow | [`.github/workflows/release.yml`](.github/workflows/release.yml) |
| Market pain research | [`docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md`](docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md) |

### Product vision (one line)

Everything Aspire can do for decorative/artistic CNC — signs, inlays, 3D relief, rotary, laser, production — in a **calm Mac UI**, with **Run on Machine** built in.

### Current implementation status (empirical)

**Done**
- SwiftUI macOS app scaffold; `swift build` green.
- Phase B shell: stages, inspector, layers browser, preferences, recipe picker, command palette, document browser panels.
- Phase C geometry kernel: `VectorShape`, `VectorPoint`, `NodeEditor`, `Transform`, `VectorOffset`, `BooleanOperations`, `JoinCloseTrim`, `SVGImporter`, `LayerManager`, `MeasurementTool`, `VectorPreflight`.
- Phase D toolpaths: Profile, Pocket, Drill, V-Carve, Quick Engrave engines; toolpath tree with dirty flags; export blocker; keep-out zones; preview simulation; GRBL post-processor; time estimator; nesting engine.
- Phase E machine control: `MachineTransport` + `SimulatorTransport`, `RealSerialTransport`, `MachineProfile`, `StatusParser`, `GCodeStreamer`, `MachineSession`, transport factory, connection UI with console/jog/zero/stream.
- Phase F sign shop: text tools, text-to-curves, text-on-curve, engraving font pack, job sheet PDF, toolpath templates, document variables panel.
- Phase G release docs + tutorial + SAFETY + keyboard shortcuts + CI workflow + packaging + versioning.
- Tests: 140+ test cases across geometry, toolpaths, streamer, status parser, preflight, export blocker, job sheet, nesting, text-on-curve, quick engrave, v-carve golden fixtures, document variables, toolpath templates, simulator integration, calibration E2E.

**Partial**
- DXF import drafted but not shipping yet; SVG path is production-ready.
- 3D relief pipeline not yet implemented (Phase H, post-v1).
- Real hardware air-cut validation pending (Phase G, human-only `[!]`).

**Not started**
- 3D relief components, sculpt, 3D rough/finish toolpaths.
- Double-sided, multi-sheet, nest advanced, inlays, rotary, laser.
- Post Studio, parametric-driven dims, notarized App Store.

## For local agents

1. Open [`AGENTS.md`](AGENTS.md) — safety + protocol.  
2. Work **only** from [`MASTER_KANBAN.md`](MASTER_KANBAN.md).
3. Loop Ready cards Phase A→G (v1.0), then H→K (full product).
4. Never idle on human `[!]` — take next Ready card. Simulator-first for machine.

**Current unblocked focus:** Phase F remaining cards (sign recipe E2E, sign recipe variables) and Phase G remaining cards.

## Stack

- **SwiftUI** macOS 14+
- **Serial:** IOKit / ORSSerialPort
- **Modules:** `ShopPilot` · `ShopPilotCore` · `ShopPilotGeometry` · `ShopPilotSerial` · `ShopPilotTests`

## Project layout

```
ShopPilot/
  AGENTS.md
  MASTER_KANBAN.md
  README.md
  Package.swift
  docs/planning/
  Sources/
  Tests/
  fixtures/gcode/
  scripts/
```

## Build

```bash
swift build
```

## License

TBD (placeholder until owner picks a license).
