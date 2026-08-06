# ShopPilot Studio — Hermes Build Todo (professional-grade CAM)

> ⚠️ **SUPERSEDED** by [`MASTER_KANBAN.md`](./MASTER_KANBAN.md).  
> Do **not** claim new work here. Kept for ID history / crosswalk only.

**Companion to:** [`HERMES_BUILD_TODO.md`](./HERMES_BUILD_TODO.md) (Machine Control)  
**Plan:** [`docs/planning/PRODUCT_VISION_PLAN.md`](./docs/planning/PRODUCT_VISION_PLAN.md)  
**Parity checklist:** [`docs/planning/FEATURE_PARITY_MATRIX.md`](./docs/planning/FEATURE_PARITY_MATRIX.md)  
**Market pain research:** [`docs/planning/MARKET_RESEARCH.md`](./docs/planning/MARKET_RESEARCH.md)  
**Last updated:** 2026-07-28  

Agents: claim `[~]`, done `[x]`, human `[!]`. Prefer **simulator** and golden fixtures. No third-party proprietary assets.

**Priority note:** **PAIN-*** and **DOC-*** items are first-class. Interleave them with capability waves — do not ship feature depth while ignoring Mac-native, preflight, dirty toolpaths, preview speed, or machine handoff.

---

## Wave DOC — Reference baseline integrity (close the FAQ gap)

> Completes honest ingestion: TOC inventory is not field-level parity.

- [ ] **DOC-01** Crawl all reference V12 form/help URLs → CSV (name, category, URL)  
  - **Cluster:** baseline · **// parallel-ok**  
  - **AC:** Row count matches docs nav; checked into the form-index CSV under `docs/planning/`
- [ ] **DOC-02** For each toolpath strategy form: map every control → ShopPilot field or intentional omission  
  - **deps:** DOC-01  
  - **AC:** Profile, Pocket, Drill, V-Carve fully mapped first; others tracked
- [ ] **DOC-03** Diff V12 → latest release notes (e.g. V12.5); update FEATURE_PARITY_MATRIX  
  - **// parallel-ok**  
  - **AC:** Matrix has “source version” column notes
- [ ] **DOC-04** Golden job pack: recreate reference tutorial/calibration projects as `.shoppilot` fixtures  
  - **deps:** STU-202+  
  - **AC:** Calibration square/circle/star job + at least one V-Carve sign fixture
- [ ] **DOC-05** Record known reference error strings (e.g. “Ignoring unsuitable open vectors”) → Preflight rule IDs  
  - **// parallel-ok**  
  - **AC:** Listed in `docs/planning/PREFLIGHT_RULES.md` with plain-English ShopPilot messages

---

## Wave PAIN — Market complaints → product fixes

> Source: user reports (Mac VM, price ladder, parametric gap, UI density, slow preview, recalc confusion, machine handoff).  
> Detail: `MARKET_RESEARCH.md` Part 2–3.

### PAIN-1 — No native Mac (cluster 1)

- [ ] **PAIN-101** Ship **native Apple Silicon** macOS app (no Windows VM required for core path)  
  - **AC:** Install/run on M-series without Parallels; docs say “Mac-native”
- [ ] **PAIN-102** **Metal** 3D canvas + preview (avoid D3D-in-VM class failures / black view)  
  - **deps:** STU-207 path · **AC:** 3D view stable under stress; no black viewport on supported GPUs
- [ ] **PAIN-103** Serial + files on host OS only (no VM file-path / USB bridging required)  
  - **deps:** Control SP-204 · **AC:** Documented connect path is host-native
- [ ] **PAIN-104** Marketing/README “Mac-native CNC studio” positioning  
  - **// parallel-ok** · **AC:** README + website stub state native Mac + no VM

### PAIN-2 — Price ladder / overkill / module friction (cluster 2)

- [ ] **PAIN-201** Define **tier packaging**: Control / Studio 2D / Studio 3D (one app binary)  
  - **Role:** PM · **AC:** Written in `docs/planning/PACKAGING.md`
- [ ] **PAIN-202** Free or low-friction path: **connect + profile/pocket + preview + run** without full 3D unlock  
  - **deps:** PAIN-201, STU-210 · **AC:** First-cut journey works on base tier
- [ ] **PAIN-203** Laser features: **included or clearly modular** — no mystery second SKU  
  - **deps:** PAIN-201 · **AC:** PACKAGING.md names laser policy
- [ ] **PAIN-204** No forced annual upgrade for basic security/compat (document policy)  
  - **Role:** PM · **AC:** Policy paragraph in PACKAGING.md

### PAIN-3 — Not parametric / weak real CAD (cluster 3)

- [ ] **PAIN-301** **Document variables** panel (named numbers usable in fields)  
  - **Related:** STU-701 · **AC:** Variable `width` drives rect size example
- [ ] **PAIN-302** **Driven dimensions** on vectors (edit dimension → geometry updates)  
  - **deps:** PAIN-301, STU-100 · **AC:** Unit test + UI demo job
- [ ] **PAIN-303** **Optional “Follow source” link** on toolpaths (opt-in auto-recalc; default **off**)  
  - **deps:** STU-206 · **AC:** Default stays safe; link mode documented
- [ ] **PAIN-304** Sign/plaque **recipe with width/height variables**  
  - **deps:** STU-007, PAIN-301 · **AC:** Change height → layout updates before toolpath calc

### PAIN-4 — UI density / thrash / cryptic errors (cluster 4)

- [ ] **PAIN-401** Enforce **≤12 primary toolbar icons** per stage (lint or design review checklist)  
  - **deps:** STU-000 · **AC:** UX checklist in PR template
- [ ] **PAIN-402** ⌘K palette: every matrix command + **plain-English synonyms**  
  - **deps:** STU-003 · **AC:** “nest”, “vcarve inlay”, “keep out” all find tools
- [ ] **PAIN-403** **Vector Preflight Doctor** before toolpath Calculate  
  - **deps:** DOC-05, STU-105 · **AC:** Detect open gaps, self-intersect, tiny segments; one-click Join/Close
- [ ] **PAIN-404** Replace cryptic errors with **fix actions** (no raw clone messages)  
  - **deps:** PAIN-403 · **AC:** “3 open gaps — Join within 0.1 mm” style UX
- [ ] **PAIN-405** **Context coach** panel (tip + link to local help for active tool)  
  - **deps:** STU-005 · **AC:** Shows on Profile / V-Carve / Job Setup
- [ ] **PAIN-406** Job recipes: calibration, sign, inlay, blank (expand STU-007)  
  - **deps:** STU-007 · **AC:** ≥4 recipes

### PAIN-5 — Slow preview / iteration (cluster 5)

- [ ] **PAIN-501** **Draft vs Final** preview modes (default Draft)  
  - **deps:** STU-207 · **AC:** Preference + toolbar toggle
- [ ] **PAIN-502** **Progressive preview** (coarse first, refine when idle)  
  - **deps:** PAIN-501 · **AC:** UI never blocked >100ms on main thread for start
- [ ] **PAIN-503** **Dirty-region / per-toolpath resim** (only resim changed paths when possible)  
  - **deps:** STU-206, STU-207 · **AC:** Edit one of two toolpaths → only that region updates
- [ ] **PAIN-504** Instant **wireframe toolpath** display before material sim completes  
  - **deps:** STU-202 · **AC:** Paths visible immediately after Calculate
- [ ] **PAIN-505** Cancel / revise preview without full wait folklore (productized “stop & edit”)  
  - **deps:** PAIN-502 · **AC:** Cancel button works mid-sim

### PAIN-6 — Toolpath ↔ art disconnect / recalc friction (cluster 6)

- [ ] **PAIN-601** **Dirty badges** on toolpath tree when source art moved/edited  
  - **deps:** STU-206 · **AC:** Badge appears after move source vectors
- [ ] **PAIN-602** **Block export/run** while any visible toolpath is dirty (with override “I know what I’m doing”)  
  - **deps:** PAIN-601, STU-209 · **AC:** Export disabled until recalc or override
- [ ] **PAIN-603** One-click **Recalculate dirty** / **Recalculate all**  
  - **deps:** PAIN-601 · **AC:** Buttons in Cut stage + palette
- [ ] **PAIN-604** **Ghost diff** optional: old vs new path after recalc  
  - **deps:** PAIN-603 · **AC:** Toggle in Preview
- [ ] **PAIN-605** In-app education: “Toolpaths don’t move with art unless Follow source is on”  
  - **// parallel-ok** · **AC:** First-time coach card

### PAIN-7 — Fragmented machine handoff (cluster 7)

- [ ] **PAIN-701** **Machine stage** end-to-end: Preview OK → post → stream (no separate sender required for GRBL)  
  - **deps:** STU-210, Control SP-305 · **AC:** Doc’d one-app cut path
- [ ] **PAIN-702** **Post auto-selected** from active machine profile  
  - **deps:** STU-209, Control profiles · **AC:** Changing machine switches post default
- [ ] **PAIN-703** **Pre-flight checklist** before Run (air-cut offer, XY/Z zero, tool, hold-downs, spindle)  
  - **deps:** PAIN-701 · **AC:** Checklist UI; can save “pro skip” in prefs
- [ ] **PAIN-704** File extension / controller format clarity (`.nc` / `.gcode` per post)  
  - **// parallel-ok** · **AC:** Save dialog shows controller-facing name
- [ ] **PAIN-705** One-click **Run on machine** after Preview acknowledgment  
  - **deps:** PAIN-701, PAIN-703 · **AC:** Single primary CTA on Machine stage

### PAIN-8 — 3D relief learning / SKU confusion (cluster 8)

- [ ] **PAIN-801** **Visual combine-mode teacher** (live Add/Subtract/Merge/Low preview)  
  - **deps:** STU-401 · **AC:** First-time Model stage interactive example
- [ ] **PAIN-802** Interactive shape handles (V12-style) as default 3D create UX  
  - **deps:** STU-403 · **AC:** Drag handles update height/angle live
- [ ] **PAIN-803** **Import-first 3D path** clearly free/base; authoring tools labeled “Model Studio”  
  - **deps:** PAIN-201 · **AC:** Empty Model state: Import STL vs Create shape
- [ ] **PAIN-804** Docs: honest “relief CAM, not full solid CAD” positioning  
  - **// parallel-ok** · **AC:** README section

### PAIN-9 — Ecosystem / gadgets / lock-in (cluster 9)

- [ ] **PAIN-901** First-party **JSON recipes** (not arbitrary unsafe scripts by default)  
  - **AC:** Recipe format doc + 2 sample recipes on disk
- [ ] **PAIN-902** Open formats first-class (SVG, DXF, STL, 3MF, G-code) in Import/Export hub  
  - **deps:** STU-106 · **AC:** Single Import/Export window
- [ ] **PAIN-903** Sandboxed plugin API design doc only (implement later)  
  - **// parallel-ok** · **AC:** `docs/planning/PLUGIN_API_DRAFT.md`

### PAIN-10 — Protect reference strengths (do not regress)

- [ ] **PAIN-A01** Profile + V-Carve remain **≤2 clicks** from Cut stage (not buried)  
  - **AC:** UX review sign-off
- [ ] **PAIN-A02** Default **no silent toolpath rewrite** when art changes  
  - **AC:** Tests assert dirty not auto-recalc
- [ ] **PAIN-A03** Sample jobs + coach ship with Phase A/B (tutorial culture)  
  - **deps:** DOC-04, PAIN-405 · **AC:** ≥3 sample projects in app
- [ ] **PAIN-A04** Stay **3-axis router focused** in messaging (no 5-axis scope creep in MVP)  
  - **// parallel-ok** · **AC:** PRODUCT_BRIEF updated

### PAIN — Research follow-ups (human + agent)

- [ ] **PAIN-R01** Browse CAM forum wishlists → top 50 themes → append to research doc  
  - **Role:** PM/research · **[!] / agent**
- [ ] **PAIN-R02** 5 interviews: incumbent users + 5 Mac CNC (Fusion/Carbide) win-loss notes  
  - **Role:** Human · **[!]**
- [ ] **PAIN-R03** Alpha survey: “Why leave/avoid the incumbent?”  
  - **Role:** PM · **deps:** alpha build

---

## Wave S0 — Platform (Phase A)

- [ ] **STU-000** App shell with Stage rail (Setup/Design/Model/Cut/Preview/Machine)  
  - AC: Switch stages; state persists; empty canvases  
- [ ] **STU-001** Document model v0: Job, Sheet (single), Layer, undo stack  
- [ ] **STU-002** Autosave + crash recovery package  
- [ ] **STU-003** ⌘K command palette framework (register stubs for all matrix IDs)  
- [ ] **STU-004** Browser panel: Layers | Components | Toolpaths | Sheets  
- [ ] **STU-005** Inspector shell (Essentials / Advanced disclosure)  
- [ ] **STU-006** Preferences: units, theme, shop checklist  
- [ ] **STU-007** Job recipe picker (blank + calibration + sign)  

## Wave S1 — Vector kernel & Design basics

- [ ] **STU-100** Geometry kernel spike: polyline, arc, circle, rect  
- [ ] **STU-101** Node editing  
- [ ] **STU-102** Transform + align + group  
- [ ] **STU-103** Offset vectors  
- [ ] **STU-104** Boolean weld / subtract / intersection  
- [ ] **STU-105** Join / close / trim  
- [ ] **STU-106** Import SVG + DXF (minimal)  
- [ ] **STU-107** Layers CRUD + visibility  
- [ ] **STU-108** Measure tool  
- [ ] **STU-109** Calculation numeric fields  
- [ ] **STU-110** Golden tests for offset/boolean  

## Wave S2 — Toolpath core loop

- [ ] **STU-200** Material setup (flat)  
- [ ] **STU-201** Tool database v0 (endmill, V-bit definitions)  
- [ ] **STU-202** Profile toolpath (outside/inside/on)  
- [ ] **STU-203** Pocket toolpath  
- [ ] **STU-204** Drill toolpath  
- [ ] **STU-205** Tabs on profile  
- [ ] **STU-206** Toolpath tree + dirty flag (no silent recalc) — **also satisfies PAIN-601 foundation**  
- [ ] **STU-207** Preview simulation heightfield — **extend with PAIN-501…505**
- [ ] **STU-208** Time estimate rough  
- [ ] **STU-209** GRBL post export  
- [ ] **STU-210** Wire export → Machine stage stream (Control module)  
- [ ] **STU-211** Keep-out zones v0  
- [ ] **STU-212** Calibration recipe end-to-end test  

## Wave S3 — Sign shop

- [ ] **STU-300** Text + fonts  
- [ ] **STU-301** Text on curve  
- [ ] **STU-302** Convert text to curves  
- [ ] **STU-303** V-Carve strategy  
- [ ] **STU-304** Quick engrave  
- [ ] **STU-305** Trace bitmap  
- [ ] **STU-306** Fillets, array copy  
- [ ] **STU-307** Nest parts v1  
- [ ] **STU-308** Job sheet PDF  
- [ ] **STU-309** Toolpath templates  

## Wave S4 — 3D composite

- [ ] **STU-400** Component + Level model  
- [ ] **STU-401** Combine modes Add/Subtract/Merge/Low  
- [ ] **STU-402** Dynamic height/tilt/fade  
- [ ] **STU-403** Shape tools: angled, round, smooth, flat  
- [ ] **STU-404** Bitmap → component  
- [ ] **STU-405** Import STL orient wizard  
- [ ] **STU-406** Export STL  
- [ ] **STU-407** Metal composite render  
- [ ] **STU-408** 3D rough toolpath  
- [ ] **STU-409** 3D finish toolpath  
- [ ] **STU-410** Zero plane + boundary from components  

## Wave S5 — Production & dual-side

- [ ] **STU-500** Multi-sheet  
- [ ] **STU-501** Double-sided job + multi-sided view  
- [ ] **STU-502** Inlay + VCarve inlay recipes  
- [ ] **STU-503** Array/merged toolpaths  
- [ ] **STU-504** Nest advanced  
- [ ] **STU-505** Tiling manager  
- [ ] **STU-506** Vector validator preflight  

## Wave S6 — Specialty, rotary, laser

- [ ] **STU-600** Fluting, texture, prism, chamfer, moulding  
- [ ] **STU-601** Photo V-Carve + Sketch carving  
- [ ] **STU-602** Thread milling  
- [ ] **STU-603** Rotary job + wrap + spiral  
- [ ] **STU-604** Rotary modelling helpers  
- [ ] **STU-605** Laser cut/fill/picture  
- [ ] **STU-606** Gadgets: keyhole, rounding, drag knife  
- [ ] **STU-607** Level mirror modes  
- [ ] **STU-608** Sculpting mode  

## Wave S7 — Power

- [ ] **STU-700** Post Studio (variables, blocks)  
- [ ] **STU-701** Document variables  
- [ ] **STU-702** Machine catalog online  
- [ ] **STU-703** Performance pass (10k vectors, large relief)  
- [ ] **STU-704** Parity matrix audit 100%  
- [ ] **STU-705** Notarized release pipeline  

---

## Parallelism notes

- **Control** (`HERMES_BUILD_TODO` SP-*) can run fully parallel through Machine stage readiness.  
- **STU-210** depends on Control SP-202+ and Studio STU-209.  
- Kernel (S1) and Platform (S0) parallel-ok after STU-000.  
- **DOC-01, DOC-03, DOC-05, PAIN-104, PAIN-201, PAIN-R*** are parallel-ok anytime.  
- **PAIN-701…705** couple tightly to Control board — claim both boards when working Machine stage.  
- Suggested early interleave: **S0 + DOC-01 + PAIN-401/402** → **S1 + PAIN-403** → **S2 + PAIN-501/601/701**.

### Suggested claim order for “beat the incumbent on experience”

1. DOC-01, PAIN-201 (packaging truth)  
2. STU-000…007 + PAIN-101/104 (native Mac shell)  
3. STU-100…110 + PAIN-403 (geometry + preflight)  
4. STU-200…212 + PAIN-501, PAIN-601, PAIN-701 (cut loop + pain wins)  
5. Continue S3+ with PAIN-301…304, PAIN-801…

---

## Work log

### 2026-07-28 — product planning
- Studied the reference V12 user guide + what’s new  
- Wrote PRODUCT_VISION_PLAN, FEATURE_PARITY_MATRIX, UX_STAGE_SYSTEM  
- Opened this Studio todo board for team/Hermes execution  

### 2026-07-28 — market pain + baseline honesty
- Added **Wave DOC** (DOC-01…05) and **Wave PAIN** (PAIN-101…R03, PAIN-A01…A04)  
- Source: `docs/planning/MARKET_RESEARCH.md`  
- Cross-linked STU-206/207 to dirty/preview pain items  

