# ShopPilot — Lean CNC Scope (agent north star)

**Last updated:** 2026-08-25  
**Overrides:** feature-count parity is **reference evidence only**. This file is the product bar for agents.

---

## One-line bar

> Offline Mac app: design vectors → **Profile / Pocket / Drill / V-Carve** + **3D rough/finish** → sheet-aware preview → **GRBL G-code** → sim/serial machine control. No cloud. No social. No video chrome.

---

## In scope (ship / harden)

| Priority | Capability |
| --- | --- |
| P0 | 2D design (draw/edit/boolean/SVG+DXF), layers, `.shoppilot` save |
| P0 | Profile, Pocket, Drill, V-Carve — real G-code, dirty/recalc, Cut UI |
| P0 | V-Carve **clearance-tool** pass before V-bit (wide letters / deep areas) |
| P0 | Sheet-aware material preview (cancellable, non-blocking) |
| P0 | GRBL post + stream (sim default; serial factory; Hold/Reset always visible) |
| P0 | **3D carving:** STL → heightfield → real rough + finish G-code; Model stage usable |
| P0 | **Cut quality of existing engines** — ball compensation + 8–12% finish stepover; V-bit tip Ø; photo groove width (not more menu items). [`CUT_QUALITY_RESEARCH_2026-08-25.md`](./CUT_QUALITY_RESEARCH_2026-08-25.md) |
| P1 | Tool DB seed + feeds wired to recalc |
| P1 | Goldens for Profile / Pocket / V-Carve / 3D vs fixture G-code |

## Explicit non-goals (do not build or surface in app)

- Cloud accounts, remote/online tool DB, online machine catalog, telemetry / crash phones-home
- In-app tutorial **videos**, YouTube / social links, remote-fed startup marketing
- Cabinet import, gadget marketplace, clipart library
- Laser / plasma / 964-post library chase; a *new* photo-CAM SKU (the existing Photo V-Carve engine may be hardened — SPK-2110)
- Proprietary CRV reverse-engineering

Offline markdown for developers (SAFETY, first-cut text) is fine. Keep it **out of app chrome**.

---

## Reference comparison (honest)

| Area | Reference | ShopPilot lean target |
| --- | --- | --- |
| 2.5D CAM | Mature | Harden algorithms + goldens — not form-field tourism |
| V-Carve | Clearance tools + engraving | Clearance chain + flat depth — match cut quality, not every gadget |
| 3D relief | Full components/sculpt | Heightfield + rough/finish G-code first; **finish = drop-cutter + 8–12% stepover** (PHASE Y); sculpt later |
| Posts | 964 | GRBL-class first-class; more posts only when a real machine needs them |
| Machine control | File out only | **Ours** — keep |
| Cloud / tutorials | Trial remote content | **Never** |

Evidence: [`INSTALLER_BREAKDOWN.md`](./INSTALLER_BREAKDOWN.md), [`FEATURE_PARITY_MATRIX.md`](./FEATURE_PARITY_MATRIX.md) §R (status column may be stale — trust Sources + MASTER_KANBAN).

---

## Finish order (lean)

1. Preview trust (sheet-aware sim) — **SPK-1103**
2. Harden 2.5D + V-Carve clearance — goldens
3. **3D carving quality** (drop-cutter finish, not more strategies) — **SPK-2100a**; do not wait for SPK-0623
4. Machine path (sim + serial); live hardware stays `[!]`
5. Prune / ignore cloud·tutorial·gadget cards marked `[-]`

Dual-side, rotary, laser, Post Studio, App Store remain post-lean.

---

## Agent protocol delta

When this conflicts with “reference parity” or “Phase H only after SPK-0623”:

1. Prefer **this file**.
2. Prefer earliest open P0 on the lean list above.
3. Never claim cards for cloud / social / in-app video / remote catalogs.
4. DoD still Engine + UI + Persist + Verify — build-only is not done.
