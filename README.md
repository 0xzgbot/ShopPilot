# ShopPilot

Native **macOS** CNC suite: Aspire-class design + toolpaths + preview, plus GRBL/FluidNC machine control.

> **Safety:** Software is not a substitute for a hardware e-stop.  
> **Scope:** Relief CAM + machine control — not full solid CAD. See [`docs/planning/PRODUCT_BOUNDARIES.md`](docs/planning/PRODUCT_BOUNDARIES.md).

## Where to work

| Doc | Role |
| --- | --- |
| [`docs/planning/FINISH_ROADMAP.md`](docs/planning/FINISH_ROADMAP.md) | **How to finish all features** (Tracks 1–6) |
| [`MASTER_KANBAN.md`](MASTER_KANBAN.md) | **Only task board** — claim SPK cards here |
| [`SHIP_CHECKLIST.md`](SHIP_CHECKLIST.md) | v1 gate checklist |
| [`AGENTS.md`](AGENTS.md) | Agent protocol + safety |

## Status (honest)

You are **not** at v1.0. Prior Kanban marks overstated completion. Board was repaired 2026-08-01:

- Finish DoD = Engine + UI + Persist + Verify
- False v1 `[x]` reopened; H–K backlog until SPK-0623
- P0 spine cards: **SPK-1100 → 1106**
- Human blockers marked `[!]`

**Next work:** SPK-1100 (document session spine), then SPK-1101 (Design editor).

## Build

```bash
swift build
swift run ShopPilot
```

Unit tests require full Xcode (not CLI tools alone):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

## Stack

SwiftUI macOS 14+ · `ShopPilot` · `ShopPilotCore` · `ShopPilotSerial` · `ShopPilotGeometry` · `ShopPilotTests`

## License

TBD.
