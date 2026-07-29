# ShopPilot — 3D Relief Finishing Strategy

**Date:** 2026-07-28  
**Purpose:** Define the finishing toolpath strategy for 3D relief geometry.

---

## Overview

The finish pass follows the roughing pass to achieve the final surface quality. Unlike roughing (which removes bulk material quickly), finishing prioritizes surface accuracy and visual quality over speed.

---

## Scallop Height Calculation

### The Core Formula

```
stepOver = sqrt(4 * R * scallopHeight)
```

Where:
- **R** = cutter radius (mm)
- **scallopHeight** = desired peak-to-valley height between adjacent passes (mm)
- **stepOver** = lateral distance between adjacent toolpath lines (mm)

### Inverse Calculation

When the user specifies a step-over and we need to report expected surface quality:

```
actualScallop = stepOver^2 / (4 * R)
```

### Example Values (Ball Nose, 6mm dia → R=3mm)

| Target Scallop | Step-Over | Surface Quality |
|---|---|---|
| 0.1 mm | 1.10 mm | Fine — sanding-free finish |
| 0.2 mm | 1.55 mm | Good — light sanding OK |
| 0.5 mm | 2.45 mm | Rough — visible tool marks |
| 1.0 mm | 3.46 mm | Very rough — not recommended for finish |

### UI Implication

The finishing form should present **scallop height** as the primary user-facing parameter (intuitive: "how smooth do I want it?"), and compute step-over internally. Display the computed step-over as secondary info.

---

## Pass Orientation Options

### 1. Parallel X (Default)

Toolpath lines run parallel to the X-axis. Best for:
- Rectangular stock with dominant grain direction along X
- Reliefs where detail flows left-to-right
- General-purpose finishing

```
→ → → → → → → → → →
→ → → → → → → → → →
→ → → → → → → → → →
```

### 2. Parallel Y

Toolpath lines run parallel to the Y-axis. Best for:
- Rectangular stock with dominant grain direction along Y
- Reliefs where detail flows front-to-back
- Avoiding visible tool marks on the primary viewing face

```
↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑
↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑
↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑
```

### 3. Radial (Spiral from Center)

Toolpath follows concentric circles or Archimedean spirals centered on the stock. Best for:
- Circular/rotary workpieces
- Reliefs with radial symmetry (portraits, medallions)
- Eliminating directional tool marks entirely

```
    ○○○○○○○○
   ○○○○○○○○○○
  ○○○○○○○○○○○○
   ○○○○○○○○○○
    ○○○○○○○○
```

### 4. Adaptive (Direction-Changing)

Toolpath direction changes based on local surface curvature. High-curvature areas get multi-directional passes; flat areas use a single dominant direction. Best for:
- Complex reliefs with varying detail density
- Minimizing total tool travel while maintaining quality
- v1.1+ enhancement (not required for v1.0)

---

## Undercut Handling

### What Are Undercuts?

An undercut is any surface feature where the cutting tool cannot reach because the geometry overhangs beyond the tool's axis. For a vertical ball nose end mill:
- Vertical walls below the top edge → unreachable
- Overhanging ledges → only partially reachable
- Inverted curves → tool tip can't follow

### ShopPilot Approach (v1.0)

**Do not attempt to cut undercuts.** The finishing pass operates on a "visible surface" model:

1. **Surface analysis:** After roughing, compute the set of points reachable by the selected finish tool from above (no lateral offset beyond tool radius).
2. **Mask unreachable areas:** Mark undercut regions as "not cut." These remain at the roughed depth.
3. **Report in preview:** Show reachable vs. unreachable zones with different colors in the 3D preview.

### User Communication

The finishing form includes a clear warning:
> "Undercut areas (vertical walls, overhangs) cannot be reached by this tool. Use a smaller diameter tool or adjust your model geometry."

### v1.1+ Enhancement

Support for angled/tilted tools (5-axis simulation) could partially address undercuts. This is out of scope for v1.0.

---

## Feed Rate Strategy for Finishing

| Parameter | Roughing | Finishing |
|---|---|---|
| Cut rate | 60–80% of max | 100% of rated feed (material-dependent) |
| Plunge rate | 50–70% of cut rate | 40–60% of cut rate (lighter cuts, still careful) |
| Rapid clearance | 2–3mm above stock | 2–3mm above stock (same) |
| Step-down | Aggressive (10–25% tool dia) | Conservative (2–5% tool dia or scallop-limited) |

### Why Finishing Can Be Faster in Feed Rate

Roughing uses conservative feed rates because:
- Full depth of cut creates high cutting forces
- Chip evacuation is critical to prevent recutting chips

Finishing uses lighter cuts, so the tool experiences less stress and can run at higher surface speeds. The limiting factor becomes **surface quality** (scallop height), not cutting force.

---

## Integration with Stage System

The finishing strategy appears in:

1. **Cut stage:** Toolpath form includes finish pass section after roughing configuration
2. **Preview stage:** Animated simulation shows roughing → finishing sequence with distinct colors
3. **Machine stage:** G-code output contains both roughing and finishing passes, separated by tool change if needed

### G-Code Structure

```gcode
; === ROUGHING PASS ===
G0 Z5.0 (rapid to clearance)
G1 Z-2.0 F200 (plunge at roughing rate)
... (roughing toolpath segments) ...

; === TOOL CHANGE (if different finish tool) ===
M6 T2 (load finish tool)

; === FINISHING PASS ===
G0 Z5.0 (rapid to clearance)
G1 Z-2.0 F300 (plunge at finishing rate)
... (finishing toolpath segments) ...
```

---

## Notes

- All formulas and strategies are derived from standard CNC machining references, not from Vectric/Aspire proprietary implementations
- Scallop height formula is universal geometry — applies to any ball nose cutter regardless of CAM software
- No Vectric proprietary assets or algorithms used
