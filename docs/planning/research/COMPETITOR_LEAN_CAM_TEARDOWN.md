# Competitor Lean CAM Teardown (Carbide Create, Estlcam, Fusion Free CAM, Candle/UGS)

**Date:** 2026-08-04 · **Method:** web research (manufacturer docs, community reviews, comparison guides) — not live app capture. Mark `[verified]` where confirmed by multiple sources, `[inferred]` where derived from reviews/docs.
**Purpose:** steal workflow simplicity for ShopPilot's lean bar; do not copy Aspire clutter. Findings feed `WHAT_IT_TAKES_CNC_APP.md` + LEAN_CNC_SCOPE.

---

## TL;DR — what the lean winners do that Aspire doesn't

1. **One design tab, one toolpath tab, one preview** — no tab maze. Carbide Create and Estlcam both ship a single vertical rail of tools; toolpath creation is a modal dialog from a selected vector.
2. **Tool = one dropdown, not a database management session.** Free tools default to a handful of common bits; feeds/speeds come from a per-material preset, not a matrix UI.
3. **Defaults are safe and visible.** Carbide Create bakes in conservative feeds; Estlcam asks material+tool and fills the rest.
4. **Preview is cheap and instant** — 3D view of the cut before saving, without a "preview all sides" ceremony.
5. **Post selection happens at save time, once** — no machine-configuration wizard tax for the 90% GRBL case.

---

## 1. Carbide Create (Carbide 3D — free / Pro)

| Aspect | Evidence |
|---|---|
| Positioning | "Purpose-built for 2D cutting… most beginner-friendly option" [verified — cncrouterinfo guide]. "Simple to a fault, but straightforward, and one can do pretty much any CAM thing one needs" [verified — Carbide community]. |
| Design surface | Single 2D canvas with toolbar; shapes/text/import DXF-SVG; boolean union/difference; no layers-heavy workflow (has some). |
| Toolpaths (free) | Profile (with tabs, lead-ins, multi-pass), Pocket, Drill, **V-Carve** [verified — docs/community]. |
| V-Carve | V-carve tool with bit angle selection; clearance tool available in **Pro** tier [verified]. |
| 3D | Free: none. Pro: 3D modelling + high-productivity toolpaths [verified — community post]. |
| Material/tool model | Choose material (wood/MDF/etc.) → app supplies feeds/speeds from its own table; tool = diameter + type dropdown. **No tool database management UI in free tier** [inferred from docs]. |
| Post/save | Posts to Carbide Motion + generic GRBL; save toolpaths; machine integration "seamless" with Carbide machines [verified]. |
| Multi-tool handling | Community advice: split file at tool change into two files (same as Vectric multi-file save) [verified — Facebook/community]. |
| What to steal | Material-preset → auto feeds/speeds (zero-config for newbies); one tool dropdown; tab dialog with count/spacing; V-carve bit angle as first-class field; **refuse to show a machine wizard when GRBL is the answer**. |
| What to skip | Carbide-machine lock-in, cloud account, Pro-gated clearance tool (ShopPilot ships it free). |

## 2. Estlcam (Christian Knüll — freemium, Windows)

| Aspect | Evidence |
|---|---|
| Positioning | "PC-first CAM tool focused on practical CNC workflows, fast part setup for hobbyist and small-shop use" [verified — gitnux]; "2.5D and basic 3D milling; clean and intuitive workflow" [verified — vsengineering]. |
| Design surface | Built-in vector drawing + import; deliberately minimal. CAD is secondary — Estlcam assumes you import DXF/SVG or draw simple shapes. |
| Toolpaths | 2.5D (profile, pocket, drill, engraving), **3D milling** (roughing + finishing) [verified — multiple guides]. |
| 3D workflow | Load STL/relief → set tool + stepover → roughing pass → finishing pass; simple 3D preview [inferred from docs/reviews]. |
| Material/tool model | Tool table (diameter, flute count, feed per material) but kept simple; material selection with suggested speeds [inferred]. |
| Post/save | Built-in post list incl. GRBL; save per-toolpath files; also has a **built-in sender** (load G-code, jog, run) — CAM + control in one app [verified — long-standing feature]. |
| Licensing | Free for ≤500 lines / non-commercial; one-time small license [verified]. |
| What to steal | **CAM + sender in one app** (ShopPilot's exact lean shape); minimal CAD (import-first); 3D rough+finish as a two-step pair; STL import first-class. |
| What to skip | Windows-only/dated UI; the free-line-count watermark; per-feature paid unlock model. |

## 3. Fusion 360 Free CAM (Autodesk — free personal use)

| Aspect | Evidence |
|---|---|
| Positioning | Parametric CAD + full CAM; "steep learning curve" [verified — cncrouterinfo table]; free tier is the hobby default. |
| Toolpaths | 2D contour/pocket/drill, **adaptive clearing**, 3D rough/finish, engrave. Huge surface. |
| Free-tier CAM limit | "Free version of Fusion will not post code for multiple tools — so if using the ATC you would need the paid version" [verified — community comment]. Forces single-tool files. |
| Material/tool model | Tool library + feeds/speeds library; per-material feeds/speeds matrix (like Vectric's DB). Powerful but heavyweight. |
| Post | Post-processor gallery incl. GRBL/grblHAL; setup wizard per machine. |
| What to steal | **Setup/stock → operations list → simulate → post** ordering discipline; the simulation panel is the trust anchor; adaptive clearing as a premium operation (not lean). |
| What to skip | Subscription/cloud/account (ShopPilot is offline); parametric CAD weight; 7-pages-of-parameters failure mode (community quote: "a minimum of 7 pages of parameters you have to know by heart") [verified — comment]; free-tier multi-tool post lock. |

## 4. Candle / UGS (G-code senders, not CAM)

| Aspect | Evidence |
|---|---|
| Candle | Lightweight GRBL sender: connect, jog, load file, run, feed-hold, alarm view. 3018-bundle default [verified — community]. |
| UGS (Universal G-code Sender) | Cross-platform (Java) sender: jog, DRO, toolpath visualization, macros, joystick support; FluidNC FAQ explicitly points users to UGS for joystick [verified — FluidNC wiki]. |
| What they prove | **The machine-control surface is small**: jog (step sizes), DRO (WPos/MPos), feed override, hold/resume/reset, alarm+unlock, file load, optional toolpath draw. That is the complete v1 machine panel. |
| What to steal | Minimal jog/zero/hold/reset chrome; DRO with MPos/WPos toggle; alarm banner + "$H/$X to unlock" hint (mirror GRBL's own `[MSG:]` text); per-file load with toolpath overlay. |
| What to skip | Java stack (UGS), no CAM ambitions, file-manager clutter. |

---

## Cross-product workflow map (for ShopPilot's lean UX)

| Step | Carbide Create | Estlcam | Fusion Free | ShopPilot lean target |
|---|---|---|---|---|
| Job start | material + size preset | material + size | stock setup | material preset + size (job setup, Vectric-proven) |
| Design | simple shapes + import | import-first | parametric CAD | vectors + text + DXF/SVG import |
| Toolpath | select vectors → dialog | select vectors → dialog | operations tree | select vectors → dialog (Vectric-style form, trimmed) |
| Tool | dropdown + material feeds | tool table | tool library | tool DB (geometry) + per-material cutting data (Vectric-proven) |
| Preview | 3D cut view | 3D view | simulation panel | sheet-aware 3D preview (SPK-1103) |
| Save | post at save | post at save + built-in sender | post gallery | GRBL-class posts + multi-file ordered save |
| Control | separate app (Motion) | built-in sender | send externally | built-in sender (Candle/UGS minimalism) |

## Steal-list (concrete, ranked)

1. **Material preset → feeds/speeds auto-fill** (Carbide) — kills the tool-DB empty-state problem for new users; ShopPilot seeds cutting-data matrix (see BIT_FEEDS_LIBRARY.md).
2. **Built-in sender as part of the app** (Estlcam) — ShopPilot's machine control is already in-scope; keep the panel Candle-minimal.
3. **Post selected at save time, defaulted per machine** (all) — no wizard tax; GRBL default.
4. **Free-tier Fusion's multi-tool limitation → make multi-file ordered save the ShopPilot feature** (Vectric-proven + Fusion-confirmed need).
5. **Preview as trust anchor** — every competitor has *some* 3D cut visualization; ShopPilot's sheet-aware preview must be instant and non-blocking.
6. **Avoid**: 7-parameter CAM forms (Fusion), tool-DB management ceremonies (Vectric), machine-wizard-first onboarding (Vectric) — progressive disclosure wins.

## Caveats

- No live app capture this pass (all competitors are closed-source desktop/web; capturing live UIs is a separate card if needed — Carbide Create and Estlcam are installable trials on macOS/Windows).
- Estlcam details partially inferred from guides/reviews, not hands-on.
- Fusion free-tier limits change; re-verify before quoting in user-facing docs.
