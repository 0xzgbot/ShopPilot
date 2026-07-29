# ShopPilot — 3D Relief Roughing Strategy

**Date:** 2026-07-28  
**Purpose:** Define the roughing toolpath strategy for 3D relief geometry.

---

## Overview

The roughing pass removes bulk material quickly, leaving a small stock allowance (typically 0.2–0.5mm) for the finishing pass to achieve final surface quality. Roughing prioritizes speed and tool life over surface finish.

---

## Algorithm: Z-Level Contouring (v1.0 Default)

### How It Works

Z-level roughing slices the model into horizontal layers at fixed step-down intervals. Within each layer, the tool follows contour lines at the intersection of the mesh and that Z-plane. This is the most reliable and widely-used 3D roughing strategy.

```
Top view (each ring = one Z-level):

    ┌──────────────┐
    │  ╭────────╮  │  ← Z=0mm (top)
    │  │ ╭─────╮│  │
    │  │ │     ││  │  ← Z=-2mm
    │  │ │     ││  │
    │  │ ╰─────╯│  │  ← Z=-4mm
    │  ╰────────╯  │
    └──────────────┘
```

### Advantages for v1.0

- **Simple to implement:** Contour extraction from mesh at each Z-plane is a well-understood algorithm (marching squares on projected grid)
- **Predictable tool loads:** Consistent chip thickness within each layer
- **GRBL-compatible:** Produces straightforward G0/G1 moves, no complex 3D interpolation needed
- **Safe:** Tool never plunges into solid material — it follows the surface at a fixed Z

### Implementation Steps

1. **Mesh rasterization:** Project the STL/OBJ mesh onto an X-Y grid with resolution = tool diameter / 4 (balances accuracy vs. performance)
2. **Z-level extraction:** For each layer from top to bottom, extract contour lines at the intersection of the mesh and the Z-plane
3. **Toolpath generation:** Offset contours outward by the tool radius to get the actual cutting path
4. **Link moves:** Connect adjacent contour segments with rapid (G0) or feed (G1) moves depending on whether the tool is in or out of material

---

## Adaptive Clearing (v1.1+ Enhancement)

### How It Differs

Adaptive clearing uses a dynamic step-over that varies based on local geometry:
- **Flat areas:** Larger step-over (faster)
- **Steep/curved areas:** Smaller step-over (maintains chip load consistency)

This reduces total tool travel compared to fixed Z-level roughing while maintaining consistent cutting forces.

### Why Not v1.0?

Adaptive clearing requires:
- 3D path planning with collision detection between passes
- Variable feed rate control based on instantaneous chip thickness
- More complex G-code output (some controllers don't support it well)

These are significant engineering efforts better suited for v1.1+.

---

## Step-Over Calculation

### Roughing Step-Over Formula

```
stepOver = 0.4 × toolDiameter
```

This is a starting point. The actual value depends on:

| Factor | Adjustment | Range |
|---|---|---|
| Tool material (carbide) | Increase step-over | Up to 50% of dia |
| Material hardness (hardwood/metal) | Decrease step-over | Down to 25% of dia |
| Machine rigidity | Decrease if loose/worn | Down to 25% of dia |

### UI Implication

The roughing form should present **step-over as a percentage of tool diameter** (default 40%), with presets:
- Aggressive (60%) — soft materials, rigid machine
- Balanced (40%) — default, good for most situations
- Conservative (25%) — hard materials, delicate machine

---

## Stock Allowance Strategy

### What Is Stock Allowance?

Stock allowance is the thin layer of material left on the surface after roughing, to be removed by the finishing pass. It ensures:
1. The finish tool always cuts fresh material (not work-hardened from roughing)
2. Surface accuracy isn't compromised by roughing tool deflection
3. The finish pass can use a smaller tool for better detail

### Recommended Values

| Finish Tool Diameter | Stock Allowance | Rationale |
|---|---|---|
| ≤ 3mm (detail work) | 0.2 mm | Fine tools need minimal stock to avoid breakage |
| 4–6mm (general purpose) | 0.3 mm | Balanced between speed and accuracy |
| ≥ 8mm (large areas) | 0.5 mm | Larger finish tools can handle more stock |

### UI Implication

The roughing form includes a "Stock to leave" field with the above defaults, auto-suggested based on the selected finish tool diameter. If no finish tool is configured yet, default to 0.3mm.

---

## Handling Steep vs Shallow Relief Angles

### Shallow Reliefs (< 15° slope)

- **Roughing approach:** Standard Z-level contouring works well
- **Step-down:** Can be aggressive (up to 50% of tool diameter) because cutting forces are low
- **Chip evacuation:** Easy — chips fall away naturally from shallow surfaces

### Steep Reliefs (> 45° slope, near-vertical walls)

- **Roughing approach:** Z-level contouring still works but may leave small uncut pockets at vertical features
- **Step-down:** Reduce to 25–30% of tool diameter for better control on steep surfaces
- **Undercuts:** Vertical walls below the top edge are unreachable by a vertical tool — these remain roughed (not finished). See THREED_FINISH_DESIGN.md for details.

### Mixed Slopes (typical portrait/relief)

Most real-world reliefs have mixed slopes. The Z-level approach handles this naturally:
- Flat areas → fast, wide passes
- Steep areas → narrower passes with tighter step-downs
- The algorithm doesn't need to change — it follows the mesh geometry at each Z-plane

### Step-Down Calculation

```
stepDown = min(0.4 × toolDiameter, stockDepth / numPasses)
```

Where `stockDepth` is the total depth of material to remove (top of model to bottom), and `numPasses` is derived from the desired step-down. The UI should show the computed number of roughing passes so the user can estimate time.

---

## Feed Rate Strategy for Roughing

| Parameter | Value | Rationale |
|---|---|---|
| Cut rate | 60–80% of finish rate | Heavier cuts require slower feed to manage chip load and tool stress |
| Plunge rate | 40–50% of cut rate | Plunging into material is the most stressful operation for the tool |
| Rapid clearance | 2–3mm above stock top | Enough to clear geometry, not so much as to waste time on air moves |
| Retract height | Between roughing levels | Lift just enough to clear chips (1–2mm) rather than all the way to rapid clearance |

---

## Integration with Stage System

The roughing strategy appears in:

1. **Cut stage:** Toolpath form — first section is "Roughing Pass" configuration
2. **Preview stage:** Animated simulation shows roughing toolpath in green, finishing in blue
3. **Machine stage:** G-code output contains roughing passes first, then (optionally) a tool change, then finishing passes

### G-Code Structure

```gcode
; === ROUGHING PASS ===
G0 Z5.0 (rapid to clearance height)
G1 Z-2.0 F200 (plunge at roughing plunge rate)
G1 X10 Y10 F300 (roughing cut rate — follow contour)
... (more roughing segments at successive Z-levels) ...

; === OPTIONAL TOOL CHANGE FOR FINISHING ===
G0 Z5.0 (rapid to clearance)
M5 (spindle stop)
M6 T2 (load finish tool — if different from roughing tool)
M3 S8000 (spindle start)

; === FINISHING PASS ===
... (finishing segments follow, see THREED_FINISH_DESIGN.md) ...
```

---

## Notes

- Z-level contouring algorithm described here is standard CNC CAM practice, not derived from any proprietary implementation
- All formulas and recommendations are based on open machining references and general engineering principles
- No Vectric proprietary assets or algorithms used
