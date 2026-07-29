# ShopPilot — 3D Relief Material Stock Design

**Date:** 2026-07-28  
**Status:** Living design doc — update as implementation progresses.

---

## Overview

The material stock setup defines the physical boundaries of the workpiece that the CNC machine will cut into. In ShopPilot's 3D relief workflow, users must define their stock dimensions and origin point before importing or creating a 3D model. This ensures toolpaths are calculated within safe bounds and the final output matches the user's physical material.

---

## Stock Dimensions

### Fields (mirroring Aspire's Material Setup form)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| **Width** | Numeric input + unit selector | `100` mm | X-axis dimension of the stock material |
| **Depth** | Numeric input + unit selector | `100` mm | Y-axis dimension of the stock material |
| **Height** | Numeric input + unit selector | `25` mm | Z-axis thickness (depth) of the stock material |

### Unit Support
- Millimeters (mm) — default for most users
- Inches (in) — toggle in Preferences or per-job via unit selector on each field
- All internal calculations use millimeters; conversion happens at input/output boundaries only.

---

## Origin Point Selection

Users choose where the coordinate system origin (0, 0, 0) is located relative to the stock:

### Options
1. **Center** — Origin at the center of the stock's top surface. X and Y range from `-width/2` to `+width/2`, `-depth/2` to `+depth/2`. Z ranges from `0` (top) to `-height` (bottom).
   - *Best for:* Symmetrical designs, relief sculptures centered on the stock.
   
2. **Corner** — Origin at one corner of the stock's top surface. X and Y range from `0` to `width`, `0` to `depth`. Z ranges from `0` (top) to `-height` (bottom).
   - *Best for:* Rectangular signs, designs aligned to one edge, users coming from GRBL/Marlin conventions where origin is typically at a corner.

### UI Implementation
- Radio button group in the Inspector panel's Material section.
- Visual indicator on the 3D canvas showing the origin point with axis arrows (red=X, green=Y, blue=Z).
- Changing origin does NOT move the imported model — it only changes where coordinates are measured from. A warning dialog appears if models are already placed when switching origin.

---

## Z-Zero Placement

### Options
1. **Top of stock** (default) — Z-zero is at the top surface of the material. All cutting depths are negative values (e.g., `-2mm` means 2mm below the top surface). This matches GRBL convention and most CAM software.
   
2. **Bottom of stock** — Z-zero is at the bottom surface. Cutting depths are positive values from the bottom up. Useful for users who want to think in terms of "how much material remains" rather than "how deep am I cutting."

### UI Implementation
- Toggle switch or radio buttons in the Material section of the Inspector panel.
- When "Bottom" is selected, all depth inputs flip sign internally but display as positive values (user-friendly).
- A small diagram shows the Z-axis direction for the selected option.

---

## Mesh-to-Stock Alignment

### How Imported Models Align to Stock

When a user imports an STL or OBJ file, ShopPilot must position it relative to the defined stock volume:

1. **Auto-center** (default): The imported mesh is centered on the X-Y plane of the stock's top surface. If the mesh height exceeds the stock height, a warning appears and the model is scaled down proportionally to fit.

2. **Bottom-aligned**: The lowest point of the mesh sits at Z-zero (top or bottom depending on Z-zero setting). This ensures the full relief depth fits within the stock.

3. **Manual positioning**: Users can drag the mesh in X, Y, and Z using interactive handles on the 3D canvas. Snap-to-grid is available for precise placement.

### Stock Bounding Box Visualization
- A wireframe box represents the stock volume on the 3D canvas.
- The imported model is rendered inside or outside this box depending on its dimensions.
- If any part of the model extends beyond the stock bounds, that region is highlighted in red with a warning tooltip: "Model exceeds stock boundaries."

### Stock Material Preview
- A semi-transparent colored overlay fills the stock volume to help users visualize their material.
- Color can be customized per-material type (wood = tan, plastic = gray, aluminum = silver) via Preferences.
- The preview updates in real-time as stock dimensions change.

---

## Integration with 2D Workflow

The same stock definition system is used for both 2D and 3D toolpaths:
- **2D toolpaths** use only the X-Y bounds of the stock (depth/height are informational).
- **3D toolpaths** use all three dimensions to calculate Z-depth moves and ensure relief features fit within the material.

This shared definition prevents confusion — users set up their material once, and both 2D and 3D stages reference the same values.

---

## Key Differences from Aspire

- **Simpler UI:** Aspire has separate Material Setup forms for flat and rotary jobs. ShopPilot uses a single unified form with an optional "Rotary" toggle that appears in later phases.
- **Live preview:** Stock dimensions update the 3D canvas in real-time as users type, rather than requiring a dialog close/reopen cycle.
- **Origin visualization:** Axis arrows on the canvas make it immediately clear where (0,0,0) is located — Aspire requires users to remember which corner was selected.
