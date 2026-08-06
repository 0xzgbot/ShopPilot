# ShopPilot — 3D Relief Tool Selection Guide

**Date:** 2026-07-28  
**Purpose:** Help users choose the right cutting tool for each 3D relief operation.

---

## Tool Types Overview

### Ball Nose End Mill (Ball End)

**Best for:** Smooth curves, organic shapes, finishing passes on complex surfaces.

| Parameter | Recommendation |
|-----------|---------------|
| Diameters | 1/8" (3.2mm), 1/16" (1.6mm), 3mm, 4mm |
| Step-over | 5–10% of diameter for fine finish; 15–20% for roughing |
| Operation | Primarily finishing; can rough with large diameters |
| Surface quality | Excellent — leaves smooth scallop pattern |

**Use cases:** Portrait reliefs, organic sculptural forms, smooth transitions between elevation zones.

### V-Bit (V-Groove)

**Best for:** Engraving, fine detail work, variable-depth line carving.

| Parameter | Recommendation |
|-----------|---------------|
| Angles | 30°, 45°, 60° (most common: 90° total included angle) |
| Diameters | 1/8" tip diameter at full width; effective cutting radius varies with depth |
| Step-over | 2–5% of tip diameter for fine detail; 10% for rough engraving |
| Operation | Engraving, lettering, fine texture work |
| Surface quality | Sharp V-grooves; not suitable for smooth surfaces |

**Use cases:** Text engraving on reliefs, fine line details, decorative borders, signature marks.

### Flat End Mill (Square End)

**Best for:** Roughing out stock removal, fast material removal, flat-bottom pockets in relief work.

| Parameter | Recommendation |
|-----------|---------------|
| Diameters | 1/4" (6mm), 3/8" (9.5mm), 1/2" (12mm) — larger for roughing |
| Step-over | 40–60% of diameter for roughing; 20–30% for finishing |
| Operation | Roughing, stock removal, flat-bottom features |
| Surface quality | Good for roughing; requires follow-up with ball nose for smooth finish |

**Use cases:** Removing bulk material before fine passes, flat areas in relief, pocket operations within relief geometry.

---

## Material Considerations

### Wood (Soft — Pine, Basswood)

- **Roughing:** 1/4"–3/8" flat end mill at high feed rate
- **Finishing:** 1/16" ball nose at moderate speed
- **Detail:** 90° V-bit for engraving
- **Speeds:** 12,000–24,000 RPM; feed 200–600 IPM

### Wood (Hard — Oak, Maple)

- Reduce feed rates by 30% compared to soft woods
- Use sharper tools more frequently
- Prefer smaller ball nose diameters for detail work

### Plastic (Acrylic, HDPE, Delrin)

- **Roughing:** 1/4" flat end mill, moderate speed
- **Finishing:** 1/8" ball nose at higher RPM (20,000–30,000)
- Avoid V-bits unless engraving — plastic can melt with narrow contact points
- Use compressed air or vacuum for chip evacuation

### Soft Metals (Brass, Aluminum)

- **Roughing:** 1/4"–3/8" carbide flat end mill at lower RPM
- **Finishing:** 1/8" carbide ball nose
- **Speeds:** 6,000–12,000 RPM for aluminum; 3,000–8,000 for brass
- Use cutting fluid or air blast
- V-bits not recommended for metals

---

## Recommended Toolpath Strategy

### Standard Relief Workflow

1. **Roughing pass** — Large flat end mill (1/4"–3/8") removes bulk material at aggressive step-over (50%)
2. **Semi-finish pass** — Medium ball nose (1/8"–3/16") reduces scallop height to acceptable level
3. **Finish pass** — Small ball nose (1/16" or 3mm) achieves final surface quality
4. **Detail engraving** — V-bit for any text, borders, or fine line work

### Quick Relief Workflow (Time-Critical)

1. **Single roughing pass** — Medium flat end mill at moderate step-over
2. **Quick finish** — Large ball nose (1/8") with generous step-over (20%)

Acceptable for prototypes and non-display pieces.

---

## Tool Database Integration

ShopPilot's tool database (SPK-G01) will store:

- Tool type (ball, flat, V-bit)
- Diameter / angle specifications
- Material compatibility flags
- Recommended speeds and feeds per material
- Manufacturer part number for reference

This enables automatic toolpath parameter suggestions when a user selects a tool from the database.

---

## Notes

- All recommendations assume rigid machine setup with proper workholding
- Actual optimal parameters depend on machine rigidity, spindle power, and tool quality
- ShopPilot will provide speed/feed calculators based on material and tool selection (future enhancement)
- No third-party proprietary data used — all values derived from standard machining handbooks and community knowledge
