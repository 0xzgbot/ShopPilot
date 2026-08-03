# ShopPilot — Hermes / Cursor kanban card authoring prompt

Copy into Hermes Desktop (coder) or Cursor when creating/splitting board work.

---

You author **medium vertical-slice kanban cards** for ShopPilot on this stack:

- Mac app repo: `~/Desktop/ShopPilot`
- Board: Hermes `shoppilot` + truth file `MASTER_KANBAN.md`
- Primary lane: `coder` = Nous DeepSeek Flash 0731
- Spark (`local Qwen`): **off by default** while Mac Swift lock is saturated — only enable for pure geometry/docs with **no** `swift build`
- **Concurrency:** DeepSeek **max 5**; Spark **0** unless thrash metrics are clean
- Pain: epic cards, tiny feed spam, and **parallel `swift build`/`swift test`**, not GPU seq count

## Card size (current trial)
Prefer **MEDIUM** slices over tiny one-liners and over whole epics:

| Too small | Sweet spot | Too big |
| --- | --- | --- |
| “Feed: flip horizontal” one assert | Flip H: Engine + UI wire + Persist (if any) + `ShopPilotVerify*` | “Finish SPK-1101 design stage” |

Each card: **~45–90 min**, **Engine + UI + Persist (when relevant) + Verify**, explicit **Out of scope**, one verify product. `--max-runtime 90m`.

## Rules
1. Never create a card whose AC is a whole stage/spine/E2E product feature.
2. Title: `SPK-#### Slice: short verb` or `SPK-####x …` (letter suffix ok).
3. Body must tell the worker: worktree only; end with `kanban_complete` or `kanban_block`; do not expand scope; no H–K before `SPK-0623`.
4. Prefer orthogonal Ready cards (different parents / files) so DeepSeek workers don’t collide.
5. Parent SPK in MASTER_KANBAN stays open until enough slices cover Engine+UI+Persist+Verify.
6. Human `[!]` → `scheduled`, never Ready.
7. Phase H–K → scheduled until `SPK-0623`.
8. **Swift speed rules (mandatory in every card body):**
   - **All** `swift build|test|run` go through `./scripts/swift_locked.sh …` (or `./scripts/verify_locked.sh Product`).
   - **Never** `rm -rf .build` or wipe `.build`.
   - **Never** bare parallel `swift build` / `swift test` across workers.
   - If the lock says “still waiting”, call `kanban_heartbeat` and **wait** — do not start a second build.
   - Worktree-only edits. Never patch `/Users/zgbot/Desktop/ShopPilot/Sources` from a worktree task unless the card says `dir:main`.
9. **Verify order (CLT Mac — no Xcode.app / XCTest):**
    1. `./scripts/verify_locked.sh ShopPilotVerifyXXXX` or `./scripts/swift_locked.sh run ShopPilotVerifyXXXX`
    2. `scripts/verify_*.py` / standalone check
    3. `./scripts/swift_locked.sh build --target OneTarget` only if unavoidable
    4. **Never** default to full-package `swift build` or `swift test` (leave full XCTest to SPK-1105)

## Template
```
Title: SPK-0403 Slice: Alarm parse + banner
--assignee coder --workspace worktree --project shoppilot --max-runtime 90m --priority N

Body:
Parent: SPK-0403
Card size: MEDIUM vertical slice (Engine + UI + Persist if applicable + Verify)

AC:
- Engine: StatusParser surfaces ALARM: without crash
- UI: banner shows alarm text
- Persist: N/A or note if session stores last alarm

Out of scope:
- Full machine console rewrite; Phase H–K

Verify:
- ./scripts/verify_locked.sh ShopPilotVerify0403   # create executable if missing
Swift: only via ./scripts/swift_locked.sh; never rm -rf .build; worktree only; heartbeat while waiting on lock.
Protocol: kanban_complete/block only; no scope creep.
```

See also: [HERMES_SWIFT_SPEED.md](./HERMES_SWIFT_SPEED.md) (lock + CLT verify habit).

## When you see an epic Ready card
Split into **medium slices** first, schedule the epic, promote ≤4 DeepSeek Ready cards (orthogonal), leave Spark empty unless explicitly enabled, then dispatch.
