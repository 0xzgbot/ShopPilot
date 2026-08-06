# ShopPilot — Mac-Native CNC Studio

**Native macOS · Apple Silicon + Intel · No Windows VM required**

---

## What is ShopPilot?

ShopPilot is a professional-grade Computer-Aided Manufacturing (CAM) application built natively for macOS. It generates CNC toolpaths from 2D vector designs and 3D relief models, then streams G-code to your machine — all without the bloat, Windows-only limitations, or subscription pricing of legacy alternatives.

## Screenshots

| Design & layers | Toolpaths & dirty gating | Machine control & safety |
| --- | --- | --- |
| ![Design](../screenshots/02-design-signage.png) | ![Cut](../screenshots/03-cut.png) | ![Machine](../screenshots/05-machine.png) |

| Setup & recipes | Preview & simulation | Model & 3D |
| --- | --- | --- |
| ![Setup](../screenshots/01-setup.png) | ![Preview](../screenshots/06-preview.png) | ![Model](../screenshots/04-model.png) |

---

## Why ShopPilot?

### Native Mac, Not a VM
ShopPilot runs natively on Apple Silicon (M1/M2/M3/M4) and Intel Macs. No Parallels, no Boot Camp, no Windows license needed. The app leverages SwiftUI for the UI and Metal for 3D rendering — technologies built specifically for macOS.

### Fair Pricing
One-time purchase with tiered feature levels. No subscription required. Start free with Core features, upgrade when you need more power.

### Integrated Machine Control
Connect your CNC machine directly from ShopPilot — jog axes, set work zero, stream G-code, and monitor status in real time. The built-in simulator lets you test everything before touching hardware.

### Smart Safety
- **Preflight checklist** — ack each item (work zero, Z0, tool loaded, material secured, workspace clear, G-code verified) before Run unlocks.
- **Dirty flag system** — prevents exporting stale toolpaths after design changes.
- **Always-visible Hold / Resume / Reset** during machine operation.
- **Simulator-first workflow** — rehearse every job in software, then cut.

---

## Key Features

| Category | Features |
|----------|----------|
| **Design** | Draw/edit vectors, import SVG/DXF/STL, offset, boolean ops (weld/subtract/intersect), join/close/trim, layers, undo/redo |
| **Toolpaths** | Profile, Pocket, Drill, V-Carve (+ clearance), Rough3D/Finish3D (Studio3D), recalc-on-edit dirty gating |
| **Machine** | Serial connection, jog/zero, G-code streaming, Hold/Reset safety controls, simulator transport |
| **Preview** | Heightfield + wireframe + combined simulation, cancellable draft sim |
| **Export** | GRBL-compatible G-code, dirty-export blocking, `.shoppilot` job packages |
| **UX** | Stage rail (≤12 icons), ⌘K command palette, recipes, context coach panel |

---

## Getting Started

1. **Install:** Download [`dist/ShopPilot-macOS.zip`](../../dist/ShopPilot-macOS.zip), unzip, drag to Applications. First launch: right-click → Open.
2. **Create a job:** Setup stage → choose a **recipe** (Signage / Decorative Panel / Portrait Relief) or set custom stock.
3. **Design:** Draw vectors or import SVG/DXF in the Design stage.
4. **Toolpaths:** Cut stage → strategy (Profile/Pocket/Drill/V-Carve) → calculate.
5. **Preview:** Simulate before exporting.
6. **Export:** Save toolpaths / send to Machine.
7. **Run:** Connect simulator or serial, preflight, run.

See [TUTORIAL_FIRST_CUT.md](./TUTORIAL_FIRST_CUT.md) for the complete step-by-step walkthrough.

---

## Safety First

ShopPilot is a toolpath generator — **you are responsible for verifying all toolpaths before running on hardware.** Always:
- Run simulations first (simulator transport included).
- Complete the preflight checklist before Run.
- Verify stock dimensions match your physical material.
- Use Hold/Reset controls during machine operation.
- Never rely on software as a substitute for a hardware e-stop.

See [SAFETY.md](./SAFETY.md) for complete safety guidelines.

---

## Documentation

| Document | Purpose |
|----------|---------|
| [TUTORIAL_FIRST_CUT.md](./TUTORIAL_FIRST_CUT.md) | End-user first-cut tutorial |
| [KEYBOARD_SHORTCUTS.md](./KEYBOARD_SHORTCUTS.md) | Keyboard shortcut reference |
| [SAFETY.md](./SAFETY.md) | Safety guidelines and compliance rules |
| [PACKAGING.md](./PACKAGING.md) | Product tiers and pricing strategy |
| [FEATURE_PARITY_MATRIX.md](./FEATURE_PARITY_MATRIX.md) | reference V12 feature comparison |
| [AGENTS.md](../AGENTS.md) | Agent operating manual (architecture, rules, workflow) |

---

## License

ShopPilot is proprietary software. No third-party proprietary assets are used in this project — all code and documentation written from scratch.
