# ShopPilot — continuous build orchestrator

**Project:** ~/Desktop/ShopPilot  
**Single source of truth:** MASTER_KANBAN.md  
**Safety:** AGENTS.md  
**Card sizing:** docs/planning/KANBAN_MICRO_CARD_PROMPT.md  

## Your job
Execute the ShopPilot product until v1.0 ships, then continue to full product (Phases H–K). Prefer **medium vertical slices** (Engine+UI+Persist+Verify, ~45–90m) over tiny feed cards and over epics. Board: Hermes `shoppilot`. Lane: **`coder` (DeepSeek) max 5**; **`spark` off** unless a card is pure non-Swift.

## Speed rules (mandatory — build thrash kills throughput)
1. **All** `swift build|test|run` via `./scripts/swift_locked.sh …` (verify: `./scripts/verify_locked.sh ShopPilotVerifyXXXX`).
2. **Never** `rm -rf .build` or wipe `.build`.
3. **Never** bare parallel `swift build` / `swift test`. If lock says “still waiting”, `kanban_heartbeat` and wait.
4. Prefer CLT verify executables (`ShopPilotVerify*`) over `swift test` (this Mac often has no Xcode.app/XCTest).
5. Worktree-only Sources edits unless card says `dir:main`.
6. Card `--max-runtime 90m`. Keep `coder` ≤5; do not spawn Spark while lock queue is multi-minute.

## Loop (never stop unless all Ready empty)
1. Read MASTER_KANBAN.md §1 protocol and current checkboxes + FINISH_ROADMAP.
2. Prefer open **SPK-1100–1106** spine / medium slices, then earliest Phase A→G Ready with deps `[x]` (prefer // P0). After SPK-0623 all [x], use H→K.
3. Implement the card AC in the **worktree** (or project root only if card says so).
4. Mark MASTER_KANBAN.md when closing a parent; `kanban_complete` / `kanban_block` for Hermes tasks; append Work log.
5. Repeat. Never idle on human [!] — pick another Ready card.
6. Simulator-first for machine work. No Vectric proprietary assets/CRV reverse-engineering.

## v1.0 must ship (Phase G)
Native Mac app, vectors, Profile/Pocket/Drill/V-Carve, preview, GRBL post, machine sim run, preflight, stage rail, dirty toolpath safety, docs.

## Start now
Dispatch Ready **medium slices** on **coder only** (≤5). Park Spark Ready. Use locked Swift + CLT verify. Split epics into medium slices before claiming them.


---
Copy this file (or the speed rules + loop) into Hermes Desktop on **coder** / **spark**.
