# ShopPilot — 3D Relief UI Design

**Date:** 2026-07-28  
**Status:** Living design doc — update as implementation progresses.

---

## Overview

The 3D relief stage in ShopPilot adds a SceneKit-powered canvas alongside the existing 2D vector workspace. The layout follows the same five-panel structure (canvas center, left panel, right panel, bottom status bar) but adapts each region for 3D-specific controls.

---

## Layout Wireframe

```
┌─────────────────────────────────────────────────────────────┐
│ Stage Rail: Setup │ Design │ Model │ Cut │ Preview │ Machine│
│                     [Model stage active]                    │
├──────────┬──────────────────────────┬───────────────────────┤
│ LEFT     │   MAIN CANVAS            │ RIGHT                 │
│ PANEL    │   (SceneKit view)        │ INSPECTOR             │
│          │                          │                       │
│ Toolpath │  ┌────────────────────┐  │ Material              │
│ Strategy │  │                    │  │ Width: [100] mm       │
│ Selector │  │   3D Relief Mesh   │  │ Depth: [25] mm        │
│          │  │   (SceneKit)       │  │ Height: [8] mm        │
│ • Rough  │  │                    │  │ Origin: ○ Center      │
│   - Step │  │                    │  │         ● Corner      │
│     over │  │                    │  │ Z-zero: ● Top         │
│   - Stock│  │                    │  │         Bottom        │
│     allow│  │                    │  │                       │
│ • Finish │  │                    │  │ Tool                  │
│   - Scal │  │                    │  │ Type: ○ Ball nose     │
│     lop  │  │                    │  │       ● V-bit         │
│   - Step │  │                    │  │       Flat end mill   │
│     over │  │                    │  │ Diameter: [6] mm      │
│ • Passes │  │                    │  │ RPM: [12000]          │
│   Rough  │  │                    │  │ Feed: [800] mm/min    │
│   Finish │  │                    │  │ Plunge: [400] mm/min  │
│          │  │                    │  │                       │
│          │  │                    │  │ Strategy              │
│          │  │                    │  │ Parallel finish       │
│          │  │                    │  │ Direction: ● X        │
│          │  │                    │  │         Y             │
│          │  │                    │  │         Radial        │
├──────────┴────────────────────────┴───────────────────────┤
│ STATUS BAR: Job time: 2h 14m | Material remaining: 3.2mm | 1 toolpath(s) | Simulated ✓                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Panel Details

### Main Canvas (SceneKit View)

- **Rendering:** SceneKit with Metal backend for GPU-accelerated 3D rendering on Apple Silicon.
- **Camera controls:** Orbit (drag), zoom (scroll/pinch), pan (middle-click/drag). Matches Aspire's 3D view controls.
- **Lighting:** Three-point lighting setup optimized for visualizing relief depth — key light at 45° angle, fill light opposite side, rim light from behind.
- **Color mapping options:**
  - Default: Mesh color with subtle shading
  - Height map: Gradient overlay (blue = low, red = high)
  - Toolpath overlay: Wireframe toolpaths rendered on top of mesh
  - Stock outline: Bounding box showing material volume
- **Performance:** LOD (level-of-detail) management for large meshes — decimate geometry when zoomed out, full resolution at close-up.

### Left Panel — Toolpath Strategy Selector

- Lists available 3D toolpath strategies in a scrollable list.
- Each strategy shows: name, icon, brief description.
- Selected strategy expands to show its parameters (step-over, stock allowance, etc.).
- Strategies include: Adaptive Rough, Step-over Rough, Parallel Finish, Scallop-height Finish, Rest Machining.

### Right Panel — Inspector

- **Material section:** Width/depth/height inputs with unit selector (mm/inch). Origin point radio buttons (center vs corner). Z-zero placement toggle (top/bottom of stock).
- **Tool section:** Tool type selector (ball nose, V-bit, flat end mill), diameter input, RPM and feed rate fields.
- **Strategy section:** Strategy-specific parameters that change based on the selected toolpath from the left panel.

### Bottom Status Bar

- Job time estimate (updated as toolpaths are calculated).
- Material remaining after job completion.
- Number of active toolpaths.
- Simulation status indicator (green checkmark when simulated, yellow warning if dirty).

---

## Integration with UX Stage System

The 3D relief stage integrates into the existing five-stage rail:

1. **Setup** — Job creation, material dimensions, machine profile selection.
2. **Design** — Vector drawing/editing (existing 2D tools).
3. **Model** — NEW stage for 3D relief work. Contains the layout above.
4. **Cut** — Toolpath management, preview, G-code export.
5. **Preview** — Machine simulation and streaming.

The Model stage sits between Design and Cut because 3D models are created in Model, then toolpaths are generated from them in Cut. This mirrors Aspire's workflow where 3D components feed into the toolpath tree.

---

## Key Differences from Aspire

- **Simpler panel layout:** Aspire has a left design panel AND right toolpath panel simultaneously. ShopPilot uses progressive disclosure — only one side panel is visible at a time, reducing visual density.
- **Metal-backed preview:** Uses SceneKit/Metal instead of OpenGL for better performance on Apple Silicon.
- **Stage rail ≤12 icons:** The Model stage icon count stays within the 12-icon limit defined in SPK-0111.
