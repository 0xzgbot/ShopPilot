# CAM User Wishlist — Top Themes from Forums

**Date:** 2026-07-28  
**Source:** Reddit r/CNC, r/hobbycnc, vendor forum community discussions.

---

## Theme 1: "Need a Mac-native alternative" (Frequency: Very High)
Users repeatedly express frustration that incumbent CAM tools are Windows-only. Many Mac users resort to Parallels or dual-booting just to use CAM software. This is ShopPilot's primary market wedge — native macOS with Apple Silicon optimization.

## Theme 2: "Subscription pricing is a dealbreaker" (Frequency: High)
The incumbent moved to a subscription model which alienated many hobbyists. Users want one-time purchase options. ShopPilot's tiered one-time purchase model directly addresses this pain point.

## Theme 3: "Slow preview/rendering" (Frequency: High)
Users complain about the incumbent's slow 3D preview and material simulation, especially on large designs. Native Metal-backed rendering in ShopPilot targets this exact complaint.

## Theme 4: "UI is cluttered / too many buttons" (Frequency: Medium-High)
The incumbent's interface has large icon matrices that overwhelm new users. The stage rail with ≤12 icons per stage and progressive disclosure directly solves this. Users want tools to appear contextually, not all at once.

## Theme 5: "Wants parametric design features" (Frequency: Medium)
Users ask for dimension-driven designs where changing one value updates the whole model. ShopPilot's document variables panel (SPK-0512) and driven dimensions (SPK-0807, v1.2+) address this.

## Theme 6: "Need better toolpath simulation" (Frequency: Medium-High)
Users want to see exactly what material will be removed before cutting. Heightfield + wireframe preview with Draft/Final modes and progressive refinement meets this need.

## Theme 7: "Frustrated by silent auto-recalculation" (Frequency: Medium)
The incumbent sometimes recalculates toolpaths silently after design changes, leading to unexpected results. ShopPilot's dirty flag system with explicit recalculate requirement solves this.

## Theme 8: "Wants better text/lettering tools for signs" (Frequency: Medium-High)
Sign-making is a core incumbent use case. Users want robust text-on-curve, text-to-curves, and V-Carve engraving — all covered in Phase F of ShopPilot's roadmap.

## Theme 9: "Need keep-out zones / pocket protection" (Frequency: Medium)
Users frequently damage tools or machines by cutting into clamped areas or already-machined pockets. Keep-out zones v0 (SPK-0308) and preflight doctor address this safety concern.

## Theme 10: "Wants better documentation/tutorials" (Frequency: Medium)
The incumbent's learning curve is steep. Users want guided workflows, recipe templates (calibration job, sign), and context-sensitive help — all covered by ShopPilot's stage system and coach panel.

## Theme 11: "Need rotary machining support" (Frequency: Low-Medium)
Some users specifically need cylindrical engraving (pens, bottles). This is a v1.3+ feature in ShopPilot's roadmap.

## Theme 12: "Wants laser cutting integration" (Frequency: Low-Medium)
Users with hybrid CNC/laser machines want both capabilities in one app. Laser support is deferred to v1.3+ per PACKAGING.md policy.

## Theme 13: "Frustrated by poor customer support / slow vendor updates" (Frequency: Medium)
Community sentiment is that the vendor moves slowly on feature requests and bug fixes. ShopPilot's open development process with public kanban board addresses this transparency gap.

## Theme 14: "Wants better file format support" (Frequency: Low-Medium)
Users want native import of SVG, DXF, STL, OBJ without conversion tools. ShopPilot supports all these formats natively.

## Theme 15: "Need offline-first / no cloud dependency" (Frequency: Medium)
Many users work in shops with unreliable internet. ShopPilot is fully offline — no account required, no cloud sync, no telemetry.

---

## Summary for Product Strategy

The top themes confirm ShopPilot's positioning: **native Mac + fair pricing + clean UI + safety-first** directly addresses the three biggest pain points (Windows-only, subscription cost, cluttered interface). Secondary themes like parametric design and rotary support are valid v1.2+ features but should not delay v1.0 ship.
