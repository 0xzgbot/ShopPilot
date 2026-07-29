# ShopPilot — Mac-Native CNC Suite

**Native Apple Silicon.** No Windows VM. No emulation layer.

---

## What Is ShopPilot?

ShopPilot is a professional-grade Computer-Aided Manufacturing (CAM) application built from the ground up for macOS on Apple Silicon. It brings Aspire-class vector design, toolpath calculation, and machine control to Mac — without requiring Parallels, VMWare, or any Windows dependency.

### What It Does

1. **Design** — Draw and edit 2D vectors: lines, arcs, circles, rectangles. Import SVG/DXF. Join, trim, offset, boolean operations.
2. **Toolpath** — Calculate cutting paths for profile, pocket, drill, and V-carve strategies using a built-in tool database.
3. **Preview** — Simulate material removal with heightfield rendering (draft + final modes).
4. **Machine Control** — Connect to GRBL-compatible CNC machines via simulator or real serial port. Stream G-code, jog axes, manage work zeros.

### What It Does NOT Do (v1.0)

- **Full 3D solid modeling** — ShopPilot handles 2D vectors and v1.1 relief components, but does not replace Fusion 360 or SolidWorks for parametric 3D CAD.
- **Laser cutting** — Laser support is planned for v1.3+; not included in any v1.0 tier.
- **Double-sided machining** — Single-sided stock only in v1.0.

---

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 14.0 (Sonoma) | 15.0 (Sequoia) |
| Chip | Apple Silicon (M1+) | M2 or newer |
| RAM | 8 GB | 16 GB+ |
| Storage | 500 MB free | 2 GB free |

**Intel Macs are not supported in v1.0.** ShopPilot is built exclusively for Apple Silicon native performance.

---

## Product Tiers

### Core (Free)
Vector design, profile/pocket/drill toolpaths, GRBL simulator, basic preview, save/open `.shoppilot` files.

### Studio (Paid Unlock)
SVG/DXF import, text-to-curves, V-carve strategy, keep-out zones, job sheet PDFs.

### Studio 3D (Paid Unlock)
Component modeling, combine modes, bitmap-to-component, 3D rough/finish toolpaths, sculpt mode.

See [PACKAGING.md](./PACKAGING.md) for full tier details and upgrade policy.

---

## Getting Started

1. **Build from source** — `swift build` produces `.build/debug/ShopPilot`
2. **Run the simulator** — Connect to the built-in GRBL simulator (no hardware required)
3. **Follow the tutorial** — See [TUTORIAL_FIRST_CUT.md](./TUTORIAL_FIRST_CUT.md) for a complete walkthrough

---

## Safety

ShopPilot is designed with safety as a first-class concern:

- **Simulator-first workflow** — Test everything on the simulator before connecting real hardware
- **Preflight checks** — Block toolpath export on invalid geometry (open vectors, out-of-bounds cuts)
- **Always-visible Hold/Reset** — Safety controls are never hidden behind menus
- **Dirty flag protection** — Cannot export G-code from dirty/unrecalculated toolpaths

See [SAFETY.md](../SAFETY.md) for the complete safety policy.

---

## Architecture

ShopPilot is structured as a Swift Package Manager multi-target project:

| Target | Purpose |
|--------|---------|
| `ShopPilot` | SwiftUI app shell, views, stages, commands |
| `ShopPilotCore` | Document model (Job/Sheet/Layer), machine transport, status parser, G-code streamer |
| `ShopPilotGeometry` | 2D vector kernel: points, shapes, nodes, transforms, offsets, booleans |
| `ShopPilotSerial` | Serial port enumeration, real serial transport, machine profiles |
| `ShopPilotTests` | Unit tests for geometry, parser, streamer |

See [ASPIRE_REIMAGINED_PRODUCT_PLAN.md](./ASPIRE_REIMAGINED_PRODUCT_PLAN.md) for the full architecture vision.

---

## License

See LICENSE file in repository root.
