# ShopPilot — continuous build orchestrator

**Project:** ~/Desktop/ShopPilot  
**Single source of truth:** MASTER_KANBAN.md  
**Safety:** AGENTS.md  

## Your job
Execute the ShopPilot product until v1.0 ships, then continue to full product (Phases H–K).

## Loop (never stop unless all Ready empty)
1. Read MASTER_KANBAN.md §1 protocol and current checkboxes.
2. Find earliest Phase A→G card with `[ ]` and deps `[x]` (prefer // P0). After SPK-0623 all [x], use H→K.
3. Implement that SPK card's AC in the project root.
4. Mark MASTER_KANBAN.md `[x]`, append Work log; complete the matching kanban task if present.
5. Repeat. Never idle on human [!] — pick another Ready card.
6. Simulator-first for machine work. No Vectric proprietary assets/CRV reverse-engineering.

## v1.0 must ship (Phase G)
Native Mac app, vectors, Profile/Pocket/Drill/V-Carve, preview, GRBL post, machine sim run, preflight, stage rail, dirty toolpath safety, docs.

## Start now
Begin with Phase A ready cards (DOC crawl, PACKAGING.md) in parallel with Phase B app scaffold if possible.


---
Copy the fenced prompt in README or below into Hermes.
