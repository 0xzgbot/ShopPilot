# ShopPilot — Scope & Honest Positioning

**Version:** 1.0  
**Last Updated:** 2026-07-30  
**SPK:** SPK-0008

---

## One-Line Statement

> **ShopPilot is a relief CAM toolpath generator and machine controller — not a full 3D solid CAD/CAM package.**

---

## What ShopPilot DOES

### 2D Vector Design
- Draw and edit 2D vectors: lines, arcs, circles, rectangles, ellipses, polygons, stars, freehand
- Node editing: move, rotate, scale, group, weld, subtract, intersect
- Import SVG (production-ready), DXF (drafted)
- Layers: create, reorder, lock, visibility toggle
- Boolean operations: weld, subtract, intersection
- Join, close, trim vectors; measure distances
- Text with system fonts (text-to-curves in v1.1+)

### Toolpath Strategies
- **Profile** — outside, inside, on-path cuts with tabs
- **Pocket** — zigzag, spiral, adaptive clearing
- **Drill** — peck, deep-hole peck, spot-drill, counterbore, countersink
- **V-Carve** — field map from DOC calibration pack
- **Quick Engrave** — surface engrave strategy
- Tool database (endmills, V-bits)
- Keep-out zones
- Dirty flags — toolpaths never silently auto-recalculate

### Preview & Simulation
- Heightfield material removal simulation (draft + final modes)
- Wireframe overlay on material
- Progressive refinement (draft → final)
- Ghost diff (old vs new path comparison)
- Rough time estimates

### Machine Control
- GRBL / FluidNC-class CNC routers over USB serial
- Built-in simulator (test everything without hardware)
- Connection status, jog, soft home, work zero
- Stream G-code with progress bar
- **Hold / Resume / Reset** — always visible, never hidden
- Pre-flight checklist before running
- One-click Run after checklist pass
- Machine profiles (GRBL / Universal)

### Documents
- `.shoppilot` save/open (single-sided stock, layers, undo, dirty doc)
- Job recipes (calibration + sign)

---

## What ShopPilot Does NOT Do (v1.0)

### Not a 3D Solid CAD System
ShopPilot is **not** a replacement for Fusion 360, SolidWorks, Rhino, FreeCAD, or any parametric 3D CAD tool. It does not:

- **3D solid modeling** — no parametric feature-based modeling
- **Full solid CAD import** — no STEP, IGES, or Parasolid import
- **Multi-axis machining** — no 4-axis or 5-axis toolpaths
- **Double-sided machining** — single-sided stock only in v1.0
- **Full 3D sculpting** — sculpt mode is Phase H (post-v1)

### Laser Cutting
Laser cutting is **NOT included in any tier for v1.0**. Laser requires different hardware (not GRBL-compatible), different safety considerations, and will be addressed in v1.3+.

### Other Exclusions
- No Windows or Linux support (macOS native only)
- No third-party proprietary asset reverse-engineering
- No App Store distribution for v1.0 (direct download + GitHub Releases)

---

## Safety — Read This

> **⚠️ CNC routers are dangerous machines. ShopPilot does not replace hardware safety.**

### Operator Requirements
- **Hardware e-stop** must be within reach and tested before every job
- Wear appropriate PPE: safety glasses, hearing protection, no loose clothing
- **Never leave a running machine unattended**
- Verify work zeros, tool length offsets, and soft limits before every job
- Always test on the simulator before running on real hardware
- First moves should be air cuts above the workpiece

### Software Safety Features
- Hold / Reset always visible while connected
- No streaming until explicit Start after file load and review
- No auto-connect or auto-run on application launch
- Dirty-flag protection: cannot export G-code from unrecalculated toolpaths
- Preflight checks block toolpath export on invalid geometry
- Spindle/coolant enable only via explicit controls

### Critical Disclaimer
> **Software controls are not a substitute for a hardware emergency stop.**  
> ShopPilot is a tool that helps you generate toolpaths and control your machine. The physical safety of you, your machine, and your workspace depends on proper hardware setup, operator awareness, and safe practices.

See [`SAFETY.md`](./SAFETY.md) for the complete safety policy.

---

## Target Audience

| ShopPilot IS for | ShopPilot is NOT for |
|---|---|
| Hobbyist CNC woodworkers | Industrial production shops |
| Sign makers & lettering artists | Multi-axis / 5-axis machining |
| Small machine shops with GRBL routers | Full parametric CAD workflows |
| Makers with desktop CNC routers | Users needing STEP/IGES import |
| Relief carving enthusiasts | Laser cutting (until v1.3+) |

---

## Where ShopPilot Fits in Your Workflow

```
CAD Tool (FreeCAD, Fusion 360, etc.)
    ↓ export 2D vectors or STL/OBJ
ShopPilot (design → toolpaths → preview → run)
    ↓ GRBL G-code
CNC Router (GRBL / FluidNC)
```

ShopPilot is designed to complement — not replace — other tools in your workflow. For parametric design from scratch, use a proper CAD tool first, then bring your designs into ShopPilot for toolpath generation and machine control.

---

## Future Roadmap (Post-v1.0)

| Phase | Feature | Target |
|---|---|---|
| H | 3D relief components, sculpt, 3D toolpaths | v1.1 |
| I | Multi-sheet, double-sided, nesting, driven dimensions | v1.2 |
| J | Rotary, laser, specialty strategies | v1.3 |
| K | Power user features, App Store, performance | v2.0 |

---

## References

- [`PACKAGING.md`](./PACKAGING.md) — Product tiers and distribution
- [`SAFETY.md`](./SAFETY.md) — Safety policy and operator checklist
- [`PRODUCT_VISION_PLAN.md`](./PRODUCT_VISION_PLAN.md) — Full product vision
- [`FEATURE_PARITY_MATRIX.md`](./FEATURE_PARITY_MATRIX.md) — reference V12 feature comparison
