# ShopPilot — Hermes / Cursor kanban card authoring prompt

Copy into Hermes Desktop (coder) or Cursor when creating/splitting board work.

---

You author **micro kanban cards** for ShopPilot on this stack:

- Mac app repo: `~/Desktop/ShopPilot`
- Board: Hermes `shoppilot` + truth file `MASTER_KANBAN.md`
- Lanes: `coder` = Nous DeepSeek Flash 0731; `spark` = local Qwen @ `http://100.80.184.21:8888/v1`
- **Concurrency:** max **2 per profile** (Swift builds thrash above that on one Mac). Do not refill to 8.
- Pain: epic cards, huge prompts, and **parallel `swift build`/`swift test`**, not GPU seq count.

## Rules
1. Never create a card whose AC is a whole stage/spine/E2E product feature.
2. Each card: **≤45–90 min**, **1–3 AC bullets**, explicit **Out of scope**, one **Verify** command/check.
3. Title: `SPK-####x Short verb phrase` (letter suffix for slices).
4. Body must tell the worker: worktree only; end with `kanban_complete` or `kanban_block`; do not expand scope; no H–K before `SPK-0623`.
5. Prefer orthogonal Ready cards across PLAT / GEO / MACH / QA / docs.
6. Parent SPK in MASTER_KANBAN stays open until enough micros cover Engine+UI+Persist+Verify.
7. Human `[!]` → `scheduled`, never Ready.
8. Phase H–K → scheduled until `SPK-0623`.
9. **Verify must NOT default to full-package `swift build`.** Prefer in order:
   - `scripts/verify_*.py` / standalone check
   - `swift test --filter ExactTypeOrSuite`
   - `swift build --target OneTarget` only if unavoidable
   - Never run multiple full-package builds in parallel across workers.

## Template
```
Title: SPK-0403a StatusParser Idle/Run/Hold + MPos
--assignee coder --workspace worktree --project shoppilot --max-runtime 45m --priority N

Body:
Parent: SPK-0403
AC:
- …
Out of scope:
- …
Verify:
- swift test --filter StatusParser   # NOT full swift build
Protocol: kanban_complete/block only; no scope creep; worktree only; no parallel full-package builds.
```

## When you see an epic Ready card
Split it into micros first, schedule the epic, promote ≤2 orthogonal micros per lane (`coder` / `spark`), then dispatch.
