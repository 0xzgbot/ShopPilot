# ShopPilot — Mac-Native CNC Studio

**Native macOS · Apple Silicon optimized · No Windows VM required**

---

## What is ShopPilot?

ShopPilot is a professional-grade Computer-Aided Manufacturing (CAM) application built natively for macOS. It generates CNC toolpaths from 2D vector designs and 3D relief models, then streams G-code to your machine — all without the bloat, Windows-only limitations, or subscription pricing of legacy alternatives.

## Why ShopPilot?

### Native Mac, Not a VM
ShopPilot runs natively on Apple Silicon (M1/M2/M3/M4) and Intel Macs. No Parallels, no Boot Camp, no Windows license needed. The app leverages SwiftUI for the UI and SceneKit/Metal for 3D rendering — technologies built specifically for macOS.

### Fair Pricing
One-time purchase with tiered feature levels. No subscription required. Start free with Core features, upgrade when you need more power.

### Integrated Machine Control
Connect your CNC machine directly from ShopPilot — jog axes, set work zero, stream G-code, and monitor status in real time. The built-in simulator lets you test everything before touching hardware.

### Smart Safety
- Preflight doctor catches open vectors, self-intersections, and out-of-bounds toolpaths before they waste material.
- Dirty flag system prevents exporting stale toolpaths after design changes.
- Always-visible Hold/Reset buttons during machine operation.
- Simulator-first workflow: test everything in software before running on hardware.

## Key Features (v1.0)

| Category | Features |
|----------|----------|
| **Design** | Draw/edit vectors, import SVG/DXF, text tools, offset, boolean ops, layers |
| **Toolpaths** | Profile, Pocket, Drill, V-Carve with material simulation preview |
| **Machine** | Serial connection, jog/zero, G-code streaming, Hold/Reset safety controls |
| **Preview** | Heightfield + wireframe simulation, Draft/Final modes, progressive refine |
| **Export** | GRBL-compatible G-code, imperial/metric variants, post-processor management |
| **UX** | Stage rail (≤12 icons), ⌘K command palette, context coach panel |

## Getting Started

1. **Install:** Download the latest `.dmg` from releases or install via Mac App Store.
2. **Create a job:** File → New Job → select stock dimensions and units.
3. **Design:** Use the Design stage to draw vectors or import SVG/DXF files.
4. **Generate toolpaths:** Switch to Cut stage, select strategy (Profile/Pocket/Drill/V-Carve), configure parameters.
5. **Preview:** Run material simulation in Preview stage before exporting.
6. **Export:** Generate G-code file for your machine controller.
7. **Run:** Connect your CNC machine via serial, load the G-code file, and run with one click.

See [TUTORIAL_FIRST_CUT.md](./planning/TUTORIAL_FIRST_CUT.md) for a complete step-by-step walkthrough.

## Safety First

ShopPilot is a toolpath generator — **you are responsible for verifying all toolpaths before running on hardware.** Always:
- Run simulations first (simulator transport included).
- Check the preflight doctor for warnings.
- Verify stock dimensions match your physical material.
- Use Hold/Reset controls during machine operation.

See [SAFETY.md](./planning/SAFETY.md) for complete safety guidelines.

## Documentation

| Document | Purpose |
|----------|---------|
| [AGENTS.md](./AGENTS.md) | Agent operating manual (architecture, rules, workflow) |
| [FEATURE_PARITY_MATRIX.md](./docs/planning/FEATURE_PARITY_MATRIX.md) | Aspire V12 feature comparison |
| [PACKAGING.md](./docs/planning/PACKAGING.md) | Product tiers and pricing strategy |
| [SAFETY.md](./docs/planning/SAFETY.md) | Safety guidelines and compliance rules |
| [TUTORIAL_FIRST_CUT.md](./docs/planning/TUTORIAL_FIRST_CUT.md) | End-user first-cut tutorial |
| [KEYBOARD_SHORTCUTS.md](./docs/planning/KEYBOARD_SHORTCUTS.md) | Keyboard shortcut reference |

## License

ShopPilot is proprietary software. See LICENSE file for terms. No Vectric proprietary assets are used in this project — all code and documentation written from scratch.
