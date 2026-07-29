# ShopPilot

Native **macOS** CNC suite: **Aspire-class design + toolpaths + preview**, plus **integrated machine control** for CNC routers (GRBL / FluidNC-class).

> **Status:** Product plan + dual agent boards. Control path + Studio (CAM) path.  
> **Safety:** Software controls are **not** a substitute for a hardware emergency stop.  
> **Research source:** [Vectric Aspire V12 User Guide](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/) (capability parity — independent implementation).

## For humans

| Item | Location |
| --- | --- |
| **Aspire reimagined master plan** | [`docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md`](docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md) |
| Feature parity matrix (~150 items) | [`docs/planning/FEATURE_PARITY_MATRIX.md`](docs/planning/FEATURE_PARITY_MATRIX.md) |
| UX stage system (anti-bloat) | [`docs/planning/UX_STAGE_SYSTEM.md`](docs/planning/UX_STAGE_SYSTEM.md) |
| Product brief (control seed) | [`docs/planning/PRODUCT_BRIEF.md`](docs/planning/PRODUCT_BRIEF.md) |
| Agent operating manual | [`AGENTS.md`](AGENTS.md) |
| **★ Master kanban (agents)** | [`MASTER_KANBAN.md`](MASTER_KANBAN.md) — single board through v1 ship → full product |
| Legacy control/studio todos | Superseded; see MASTER_KANBAN crosswalk |
| Market pain research | [`docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md`](docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md) |

### Product vision (one line)

Everything Aspire can do for decorative/artistic CNC — signs, inlays, 3D relief, rotary, laser, production — in a **calm Mac UI**, with **Run on Machine** built in.

### Dual-track MVP

**Control:** serial connect, jog, stream, hold, simulator.  
**Studio A:** job setup, vectors, profile/pocket/drill, preview, GRBL post → machine.

## For local Hermes agents

1. Open [`AGENTS.md`](AGENTS.md) — safety + protocol.  
2. Work **only** from [`MASTER_KANBAN.md`](MASTER_KANBAN.md).  
3. Loop Ready cards Phase A→G (v1.0), then H→K (full product).  
4. Never idle on human `[!]` — take next Ready card. Simulator-first for machine.

**Suggested first prompt:**

```
You are building ShopPilot at ~/Desktop/ShopPilot.
Single source of truth: MASTER_KANBAN.md
Read AGENTS.md safety rules. No Vectric proprietary assets.
Loop: claim next Ready SPK card (deps met), implement AC, mark [x], work log, repeat.
Prioritize Phase A→G until v1.0 ship. After SPK-0623, continue H→K.
Never idle on [!] — pick another Ready card. Simulator-first for machine work.
```

## Stack

- **SwiftUI** macOS 14+
- **Serial:** IOKit and/or ORSSerialPort
- **Modules:** ShopPilot (app) · ShopPilotCore · ShopPilotSerial · ShopPilotTests

## Project layout

```
ShopPilot/
  AGENTS.md
  HERMES_BUILD_TODO.md
  README.md
  docs/planning/
  Sources/
  Tests/
  fixtures/gcode/
  scripts/
  research/
```

## License

TBD (placeholder until owner picks a license).
