# ShopPilot — User Wishlist & Forum Pain Points Summary

**Date:** 2026-07-30  
**Source:** Web research across r/CNC, r/vcarve, Vectric forums, and CAM community discussions  
**Purpose:** Identify top user complaints and feature requests to prioritize ShopPilot development

---

## Top Themes

### 1. Mac-Only Demand — #1 Market Wedge
- **Complaint:** "Aspire/VCarve are Windows-only. I have to use Parallels or dual-boot just to use CAM software."
- **Software:** Aspire, VCarve, Fusion 360
- **Frequency:** Extremely high — mentioned in virtually every CNC forum thread about CAM software
- **Relevance to ShopPilot:** **HIGH** — This is ShopPilot's primary competitive advantage. Native macOS + Apple Silicon optimization directly addresses this pain.

### 2. Pricing Pain — $1500+ for Full Suite
- **Complaint:** "Aspire is too expensive for hobbyists. $1500 for the full version is a lot when I only need V-Carve and basic 2D."
- **Software:** Aspire, VCarve Pro
- **Frequency:** High — recurring theme on r/CNC and Vectric forums
- **Relevance to ShopPilot:** **HIGH** — ShopPilot's three-tier model (Core/Studio/Studio3D) with affordable entry points directly addresses this.

### 3. V-Carve Text-to-Curves Essential for Sign Makers
- **Complaint:** "I need to be able to convert text to curves for V-Carve engraving. Aspire does this but the workflow is clunky."
- **Software:** Aspire, VCarve
- **Frequency:** High — sign makers repeatedly request this feature
- **Relevance to ShopPilot:** **HIGH** — SPK-0501 (Text to curves) and SPK-0504 (V-Carve) directly target this use case.

### 4. Slow Toolpath Recalculation on Complex Designs
- **Complaint:** "Aspire freezes for 30 seconds when I change a dimension on a complex design. I just want to edit and go."
- **Software:** Aspire, Fusion 360
- **Frequency:** Medium-high — especially among users with large vector files
- **Relevance to ShopPilot:** **MEDIUM** — ShopPilot's dirty-region resimulation (SPK-0315) and toolpath tree architecture address this.

### 5. Preview Accuracy — "What You See Is What You Cut"
- **Complaint:** "The preview in Aspire doesn't always match the actual cut. I need to trust the simulation before running."
- **Software:** Aspire, VCarve
- **Frequency:** Medium — critical trust issue for hobbyists who can't afford material waste
- **Relevance to ShopPilot:** **HIGH** — ShopPilot's heightfield preview (SPK-0309) and Metal-backed rendering (SPK-0311) target this.

### 6. GRBL Compatibility & Machine Control
- **Complaint:** "I wish there was a Mac-native machine control app that works with my GRBL controller. Most options are Windows-only or require extra software."
- **Software:** Universal — affects all GRBL-based CNC users
- **Frequency:** Medium-high — especially among hobbyists with DIY machines
- **Relevance to ShopPilot:** **HIGH** — ShopPilot's integrated machine control (Phase E) with simulator-first development directly addresses this.

### 7. SVG Import Reliability
- **Complaint:** "SVG import in Aspire sometimes fails or produces unexpected results. DXF import is even worse."
- **Software:** Aspire, VCarve, Inkscape
- **Frequency:** Medium — common frustration for users who design in external tools
- **Relevance to ShopPilot:** **HIGH** — ShopPilot's SVG importer (SPK-0206) and ImportHubView (SPK-0216) are priorities.

### 8. Need for Better Documentation & Tutorials
- **Complaint:** "Vectric's documentation is good but scattered. I wish there was a single place that walks me through a complete project from start to finish."
- **Software:** Aspire, VCarve, Fusion 360
- **Frequency:** Medium — especially among new CNC users
- **Relevance to ShopPilot:** **MEDIUM** — ShopPilot's first-cut tutorial (SPK-0610) and context coach panel (SPK-0112) address this.

### 9. Tab Placement & Hold-Down Concerns
- **Complaint:** "Aspire's tab placement is too simple. I need more control over where tabs go, how many, and their size."
- **Software:** Aspire, VCarve
- **Frequency:** Medium — important for serious sign makers and production users
- **Relevance to ShopPilot:** **MEDIUM** — Profile toolpath tabs (SPK-0302) cover basic tab support.

### 10. Multi-Sheet / Production Workflow
- **Complaint:** "I have to manage multiple sheets manually in Aspire. A built-in multi-sheet workflow would save me hours."
- **Software:** Aspire, VCarve
- **Frequency:** Medium — relevant for production users with large stock
- **Relevance to ShopPilot:** **LOW (v1.0)** — Multi-sheet management (SPK-0800) is Phase I (post-v1).

---

## Summary for Prioritization

| Priority | Theme | ShopPilot Action |
|----------|-------|------------------|
| **P0** | Mac-native CAM | Ship Phase A–G (v1.0) |
| **P0** | Affordable pricing | Three-tier packaging (Core/Studio/Studio3D) |
| **P0** | V-Carve sign making | Complete SPK-0504 + SPK-0510 |
| **P1** | Preview accuracy | Heightfield + Metal preview (already done: SPK-0309/0311) |
| **P1** | GRBL machine control | Simulator integration (SPK-0417 done) |
| **P1** | SVG/DXF import | ImportHub (SPK-0216 done) |
| **P2** | Toolpath performance | Dirty-region resim (SPK-0315 done) |
| **P2** | Documentation | Tutorial + coach panel (done) |
| **P3** | Tab placement | Profile toolpath tabs (done) |
| **P3** | Multi-sheet | Phase I (post-v1) |

---

## Competitive Positioning

ShopPilot's unique advantages vs. Aspire/VCarve:

1. **Native macOS** — No Parallels, no VM, no Windows dependency
2. **Apple Silicon optimization** — Metal preview, native performance
3. **Transparent pricing** — Tiered model vs. $1500+ all-or-nothing
4. **Open ecosystem** — GRBL/FluidNC native support, no vendor lock-in
5. **Safety-first** — Preflight checks, hold/reset always visible, simulator-first
