# SPK-0605 — Stage Density Audit

## Requirement
≤12 primary icons per stage rail.

## Audit
- File: `Sources/ShopPilot/StageEnum.swift`
- File: `Sources/ShopPilot/StageRailView.swift`

### Stage enumeration
```
Stage.allCases:
  1. setup     — gearshape
  2. design    — pen.toolpath
  3. model     — cube.box
  4. cut       — scissors
  5. preview   — play.circle
  6. machine   — printer.tray
```

**Count: 6 icons**

## Result
✅ **PASS** — 6 ≤ 12. Stage rail is within density limit.

## Notes
- `Stage.allCases` has exactly 6 cases.
- `StageRailView` renders all cases in a single `HStack` via `ForEach(Stage.allCases)`.
- No dynamic stage addition paths exist — the enum is the single source of truth.
- Future stage additions must be added to `Stage` enum; the rail will auto-adapt.

---

_Audit date: 2026-07-30_
