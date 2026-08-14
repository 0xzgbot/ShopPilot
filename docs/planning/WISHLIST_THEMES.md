# CAM User Wishlist — Top Themes from Forums

**Date:** 2026-07-28  
**Source:** Reddit r/CNC, r/hobbycnc, vendor forum community discussions.

---

## Theme 1: "Need a Mac-native alternative" (Frequency: Very High)
**Resolution (2026-08-11): SHIPPED** — native macOS app (the wedge itself).

Users repeatedly express frustration that incumbent CAM tools are Windows-only. Many Mac users resort to Parallels or dual-booting just to use CAM software. This is ShopPilot's primary market wedge — native macOS with Apple Silicon optimization.

## Theme 2: "Subscription pricing is a dealbreaker" (Frequency: High)
**Resolution (2026-08-11): SCOPE-CHANGED** — personal use only, never for sale; no pricing model needed (SPK-0010/0614/0615 deferred forever).

The incumbent moved to a subscription model which alienated many hobbyists. Users want one-time purchase options. ShopPilot's tiered one-time purchase model directly addresses this pain point.

## Theme 3: "Slow preview/rendering" (Frequency: High)
**Resolution (2026-08-11): SHIPPED** — dirty-region resimulation (SPK-0315), cancellable non-blocking preview, async recalc (SPK-1314).

Users complain about the incumbent's slow 3D preview and material simulation, especially on large designs. Native Metal-backed rendering in ShopPilot targets this exact complaint.

## Theme 4: "UI is cluttered / too many buttons" (Frequency: Medium-High)
**Resolution (2026-08-11): SHIPPED** — stage rail ≤12 icons, progressive disclosure, context menus (SPK-1204), coach strip (SPK-1205), visual wave.

The incumbent's interface has large icon matrices that overwhelm new users. The stage rail with ≤12 icons per stage and progressive disclosure directly solves this. Users want tools to appear contextually, not all at once.

## Theme 5: "Wants parametric design features" (Frequency: Medium)
**Resolution (2026-08-11): SHIPPED** — document variables + expression calc (SPK-0512/0209/1001), driven dimensions (SPK-0807), dimension handles (SPK-1203).

Users ask for dimension-driven designs where changing one value updates the whole model. ShopPilot's document variables panel (SPK-0512) and driven dimensions (SPK-0807, v1.2+) address this.

## Theme 6: "Need better toolpath simulation" (Frequency: Medium-High)
**Resolution (2026-08-11): SHIPPED** — surface-color material sim (SPK-1202), sheet-aware stock (SPK-1316), peck viz (SPK-1210), hover highlight.

Users want to see exactly what material will be removed before cutting. Heightfield + wireframe preview with Draft/Final modes and progressive refinement meets this need.

## Theme 7: "Frustrated by silent auto-recalculation" (Frequency: Medium)
**Resolution (2026-08-11): SHIPPED** — dirty flags + explicit recalc (SPK-1207), status dots, no silent auto-recalc.

The incumbent sometimes recalculates toolpaths silently after design changes, leading to unexpected results. ShopPilot's dirty flag system with explicit recalculate requirement solves this.

## Theme 8: "Wants better text/lettering tools for signs" (Frequency: Medium-High)
**Resolution (2026-08-11): SHIPPED** — text-to-curves, text on curve, 3D text relief (SPK-1319).

Sign-making is a core incumbent use case. Users want robust text-on-curve, text-to-curves, and V-Carve engraving — all covered in Phase F of ShopPilot's roadmap.

## Theme 9: "Need keep-out zones / pocket protection" (Frequency: Medium)
**Resolution (2026-08-11): SHIPPED** — keep-out zones + preflight doctor.

Users frequently damage tools or machines by cutting into clamped areas or already-machined pockets. Keep-out zones v0 (SPK-0308) and preflight doctor address this safety concern.

## Theme 10: "Wants better documentation/tutorials" (Frequency: Medium)
**Resolution (2026-08-11): SHIPPED** — recipes, sample projects (SPK-1313), coach strip, TUTORIAL_FIRST_CUT.

The incumbent's learning curve is steep. Users want guided workflows, recipe templates (calibration job, sign), and context-sensitive help — all covered by ShopPilot's stage system and coach panel.

## Theme 11: "Need rotary machining support" (Frequency: Low-Medium)
**Resolution (2026-08-11): SHIPPED** — rotary setup (SPK-0903), wrap 2D/spiral (SPK-0904), rotary goldens (SPK-0909).

Some users specifically need cylindrical engraving (pens, bottles). This is a v1.3+ feature in ShopPilot's roadmap.

## Theme 12: "Wants laser cutting integration" (Frequency: Low-Medium)
**Resolution (2026-08-11): SHIPPED** — laser cut/fill/picture (SPK-0906), laser goldens (SPK-0909).

Users with hybrid CNC/laser machines want both capabilities in one app. Laser support is deferred to v1.3+ per PACKAGING.md policy.

## Theme 13: "Frustrated by poor customer support / slow vendor updates" (Frequency: Medium)
**Resolution (2026-08-11): N/A** — personal-use app; no vendor support relationship.

Community sentiment is that the vendor moves slowly on feature requests and bug fixes. ShopPilot's open development process with public kanban board addresses this transparency gap.

## Theme 14: "Wants better file format support" (Frequency: Low-Medium)
**Resolution (2026-08-11): SHIPPED** — SVG/DXF/EPS/PDF/AI/DWG import (SPK-0216), WebP (SPK-1209), import torture (SPK-1323), design PDF export (SPK-1322).

Users want native import of SVG, DXF, STL, OBJ without conversion tools. ShopPilot supports all these formats natively.

## Theme 15: "Need offline-first" (Frequency: Medium)
**Resolution (2026-08-11): SHIPPED** — fully offline, no account/telemetry.

Many users work in shops with unreliable internet. ShopPilot is fully offline — no account required, no telemetry.

---

## Summary for Product Strategy

The top themes confirm ShopPilot's positioning: **native Mac + fair pricing + clean UI + safety-first** directly addresses the three biggest pain points (Windows-only, subscription cost, cluttered interface). Secondary themes like parametric design and rotary support are valid v1.2+ features but should not delay v1.0 ship.
