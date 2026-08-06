# ShopPilot — Product Boundaries & Scope

**Version:** 1.0  
**Last Updated:** 2026-07-30

---

## What ShopPilot Is

ShopPilot is a **relief CAM toolpath generator and machine controller** for macOS. It is built from the ground up for Apple Silicon and targets the hobbyist and small-shop CNC router user.

> **One-line summary:** ShopPilot helps you design 2D vectors, calculate cutting toolpaths, preview the result, and run a CNC router — all in one native Mac app.

---

## What ShopPilot DOES (v1.0)

### Design
- **2D vector drawing:** lines, arcs, circles, rectangles, ellipses, polygons, stars, freehand
- **Node editing:** move, rotate, scale, group, weld, subtract, intersect
- **Import:** SVG (production-ready), DXF (drafted)
- **Layers:** create, reorder, lock, visibility toggle
- **Text:** system fonts, text creation (text-to-curves in v1.1+)
- **Boolean operations:** weld, subtract, intersection
- **Join/trim/close** vectors; measure distances

### Toolpaths
- **Profile** (outside, inside, on-path) with tabs
- **Pocket** (zigzag, spiral, adaptive clearing)
- **Drill** (peck, deep-hole peck, spot-drill, counterbore, countersink)
- **V-Carve** (field map from DOC calibration)
- **Quick Engrave** strategy
- Tool database (endmills, V-bits)
- Keep-out zones
- Dirty flags — no silent auto-recalculation

### Preview
- Heightfield material simulation (draft + final modes)
- Wireframe overlay
- Progressive refinement (draft → final)
- Ghost diff (old vs new path comparison)
- Time estimate (rough)

### Machine Control
- **GRBL / FluidNC-class** CNC routers over USB serial
- Built-in simulator (no hardware required)
- Connection status, jog, soft home, work zero
- Stream G-code with progress
- **Hold / Resume / Reset** — always visible
- Pre-flight checklist before running
- One-click Run after checklist pass
- Machine profiles (GRBL / Universal)

### Documents
- `.shoppilot` save/open format (single-sided stock)
- Undo/redo with dirty-document protection
- Job recipes (calibration + sign)

---

## What ShopPilot Does NOT Do (v1.0)

### Not a 3D Solid CAD System
ShopPilot is **not** a replacement for Fusion 360, SolidWorks, Rhino, FreeCAD, or any parametric 3D CAD tool. It does not:

- **3D solid modeling** — no parametric feature-based modeling
- **Full solid CAD import** — no STEP, IGES, or Parasolid import in v1.0
- **Multi-axis machining** — no 4-axis or 5-axis toolpaths
- **Double-sided machining** — single-sided stock only in v1.0
- **Full 3D sculpting** — sculpt mode is planned for Phase H (post-v1)

### Laser Cutting
Laser cutting is **not included in any tier for v1.0**. Laser requires different hardware (not GRBL-compatible), different safety considerations, and will be addressed in v1.3+.

### Other Exclusions (v1.0)
- No Windows or Linux support (macOS native only)
- No third-party proprietary asset reverse-engineering
- No App Store distribution (direct download + GitHub Releases only for v1.0)

---

## Target Audience

| Who it IS for | Who it is NOT for |
|---|---|
| Hobbyist CNC woodworkers | Industrial production shops |
| Sign makers & lettering artists | Multi-axis / 5-axis machining |
| Small machine shops | Full parametric CAD workflows |
| Makers with GRBL routers | Users needing STEP/IGES import |
| Relief carving enthusiasts | Laser cutting (until v1.3+) |

**Positioning:** ShopPilot is a friendly, Mac-native tool for people who already have (or plan to get) a hobby-grade CNC router and want to go from design to cutting in one app. It is not a full CAD/CAM suite for industrial use.

---

## Relationship to Other Tools

ShopPilot is designed to **complement** (not replace) other tools in your workflow:

- **CAD tools** (Fusion 360, FreeCAD, Rhino, TinkerCAD) → create your 3D geometry or 2D designs
- **ShopPilot** → take 2D vectors (or future STL/OBJ imports) → generate toolpaths → preview → run on your CNC router
- **Other CAM tools** → ShopPilot fills the gap for Mac users who want a professional-grade experience natively

---

## Safety

See [`SAFETY.md`](./SAFETY.md) for the complete safety policy. Key points:

- **Software is not a substitute for a hardware emergency stop.**
- CNC routers are dangerous machines — always follow proper safety procedures.
- Wear appropriate PPE (safety glasses, hearing protection, no loose clothing).
- Never leave a running machine unattended.
- Always test on the simulator before running on real hardware.
- Verify work zeros, tool length offsets, and soft limits before every job.

---

## Future Roadmap (Post-v1)

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
