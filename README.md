# ShopPilot

Native **macOS** CNC suite: **Aspire-class design + toolpaths + preview**, plus **integrated machine control** for CNC routers (GRBL / FluidNC-class).

> **Status:** Active development. Phase B shell complete. Phase C geometry core in progress (Kernel, SVG import, Layers, Measure done). Machine control scaffolded (serial + simulator + G-code streamer). Build is green.
> **Safety:** Software controls are **not** a substitute for a hardware emergency stop.
> **Research source:** [Vectric Aspire V12 User Guide](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/) (capability parity — independent implementation).

## For humans

| Item | Location |
| --- | --- |
| **Master kanban (single source of truth)** | [`MASTER_KANBAN.md`](MASTER_KANBAN.md) |
| Agent operating manual | [`AGENTS.md`](AGENTS.md) |
| Product plan | [`docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md`](docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md) |
| Feature parity matrix | [`docs/planning/FEATURE_PARITY_MATRIX.md`](docs/planning/FEATURE_PARITY_MATRIX.md) |
| Safety + in-app disclaimer | [`docs/planning/SAFETY.md`](docs/planning/SAFETY.md) |
| First-cut tutorial | [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md) |
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
- Phase B shell: stages, inspector, layers browser, preferences, recipe picker, command palette.
- Phase C geometry kernel: `VectorShape`, `VectorPoint`, `NodeEditor`, `Transform`, `VectorOffset`, `BooleanOperations`, `JoinCloseTrim`, `SVGImporter`, `LayerManager`, `MeasurementTool`.
- Phase E machine control: `MachineTransport` + `SimulatorTransport`, `RealSerialTransport`, `MachineProfile`, `StatusParser`, `GCodeStreamer`, `MachineSession`.
- Phase G release docs + tutorial + SAFETY.md + CI workflow.

**Partial**
- DXF import drafted but not shipping yet; SVG path is production-ready.
- Toolpaths: `ToolDatabase` v0 present; strategy code not yet implemented.
- Tests scaffold exists; geo/mach coverage still minimal.

**Not started**
- Full toolpath strategies: profile, pocket, drill, V-carve.
- Post processor / GRBL export.
- 3D relief pipeline.
- Real hardware air-cut validation.

## For local agents

1. Open [`AGENTS.md`](AGENTS.md) — safety + protocol.  
2. Work **only** from [`MASTER_KANBAN.md`](MASTER_KANBAN.md).  
3. Loop Ready cards Phase A→G (v1.0), then H→K (full product).  
4. Never idle on human `[!]` — take next Ready card. Simulator-first for machine.

**Current unblocked focus:** finish remaining Phase C geometry cards, then Phase D toolpath core.

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
