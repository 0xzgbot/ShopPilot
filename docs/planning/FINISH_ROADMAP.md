# ShopPilot — Finish Roadmap (source of truth for completion)

**Last updated:** 2026-08-01  
**Companion board:** [`MASTER_KANBAN.md`](../../MASTER_KANBAN.md)  
**Intent:** Finish **all** product features to Definition of Ship, then Phases H→K.  
**Not the goal:** Thin demos, manual babysitting, or “build passes = done.”

---

## Definition of Done (every card)

A card may be `[x]` only when **all four** are true:

| Layer | Meaning |
| --- | --- |
| **Engine** | Real algorithm / protocol (not estimate-only / synthetic stub) |
| **UI** | Reachable from the stage rail / menus for that feature |
| **Persist** | Survives save/open of `.shoppilot` (or machine profile JSON) where applicable |
| **Verify** | Automated test or golden proves behavior (XCTest when toolchain available) |

`swift build` alone is **never** enough.

---

## Current inventory (honest)

| Area | Library code | Product-finished |
| --- | --- | --- |
| App shell / stages | Wired spine exists | Partial — browser/inspector/doc round-trip incomplete |
| Geometry kernel | Substantial | **No** — not a full Design editor product |
| 2D toolpath engines | Profile/Pocket/Drill/VCarve emit G-code | **No** — Cut tree/UI/dirty/recalc not productized |
| Preview / Metal | Partial / stubby | **No** |
| Machine sim + serial | Substantial | Partial — handoff/tests/CI incomplete |
| Sign shop | Partial engines + panels | **No** — E2E recipe not product-complete |
| Phase H–K | Mostly data-model stubs | **No** — correctly backlog |

---

## Finish tracks (execute in order)

### Track 0 — Board hygiene (this doc + Kanban)
- Reopen false `[x]` where AC unmet  
- Human blockers → `[!]`  
- Agents work earliest open P0 with deps met  

### Track 1 — Document spine (Phase B finish) // P0
**Cards:** SPK-1100, SPK-0103, SPK-0104, SPK-0105, SPK-0106, SPK-0107  
- One `AppSession` owns job, layers, vectors, toolpaths, selection, undo, dirty  
- Save/open round-trips vectors + toolpaths + document variables  
- Browser/inspector bind to real document data  
- ⌘K routes to session actions (not stubs)  

**Exit:** Every later feature attaches to one document session.

### Track 2 — Design product (Phase C finish) // P0
**Cards:** SPK-1101, SPK-0201–0216 (reopened as needed), SPK-0206 DXF decision  
- Vector editor: create/select/move/node-edit shapes on canvas  
- Layers CRUD in UI; measure; offset/boolean/join/trim reachable  
- SVG import into document; DXF implement **or** remove from UI  
- Preflight doctor in Design with **implemented** fixes only  

**Exit:** Closed vector designs creatable and savable in-app.

### Track 3 — Toolpaths + post + preview (Phase D + F finish) // P0
**Cards:** SPK-1102, SPK-1103, SPK-0300–0319, SPK-0500–0513  
- Toolpath tree in Cut with Profile/Pocket/Drill/V-Carve params UI  
- Dirty badges, explicit recalc, export block  
- GRBL post from tree; material + tool DB wired to strategies  
- Preview stage shows toolpath + material sim (non-blocking)  
- Sign recipe: text → curves → V-Carve as one document flow  

**Exit:** Saved job regenerates toolpaths and exports GRBL.

### Track 4 — Machine product (Phase E finish) // P0 parallel after Track 1
**Cards:** SPK-1104, SPK-0400–0418, SPK-0419 `[!]`  
- Sim default; serial via factory; **no** auto-connect / auto-run  
- Stream session G-code; Hold/Resume/Reset always visible when connected  
- Preflight gate + one-click Start; console TX/RX  
- Soft-limit awareness when travel known  

**Exit:** Same document G-code streams on sim; serial ready without a second path.

### Track 5 — v1 gate (Phase G finish) // P0
**Cards:** SPK-1105, SPK-0600–0607, SPK-0610–0613, SPK-0620–0623  
- XCTest green under Xcode/CI (not build-only smoke)  
- Calibration + sign goldens automated  
- Docs match real behavior; ship checklist signed only after Tracks 1–4  

**Exit:** v1.0 Definition of Ship met → SPK-0623 `[x]`.

### Track 6 — Post-v1 (Phases H→K) // only after Track 5
Rebuild honestly — heightfields, real 3D toolpaths, dual-side, rotary/laser, Post Studio, distribution.  
Stub estimators / `PowerUser` packaging enums do **not** close cards.

---

## Critical path

```text
Track0 → Track1 → Track2 → Track3 → Track5
              ↘ Track4 ↗
Track6 only after Track5 (SPK-0623)
```

---

## Agent rules (finish mode)

1. Work **only** from `MASTER_KANBAN.md`; follow this roadmap for order.  
2. Prefer **vertical feature slices** (engine+UI+persist+verify).  
3. Never mark H–K `[x]` until Track 5 complete.  
4. Never idle on `[!]` — take next Ready card.  
5. Do **not** ask the human to dogfood mid-track; prove with tests/goldens.  
6. Human-only: license, Apple creds, live air-cut, interviews.

---

## Human blockers `[!]`

| ID | Item |
| --- | --- |
| SPK-0010 | Interviews (optional for v1) |
| SPK-0419 | Live hardware air-cut |
| SPK-0614 | License text |
| SPK-0615 | Apple Developer credentials |
| SPK-0621 | Notarized pipeline (deps 0615) |
| SPK-1009 | App Store submission (post-v1) |
