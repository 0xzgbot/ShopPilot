# ShopPilot — Ship Checklist (personal use)

**Last reviewed:** 2026-08-04  
**Scope:** Personal Mac use only — **not** App Store / notarized public distribution.  
**Board:** [`MASTER_KANBAN.md`](MASTER_KANBAN.md)  
**UI driver:** [`docs/planning/UI_ACCEPTANCE_DRIVER.md`](docs/planning/UI_ACCEPTANCE_DRIVER.md)  
**Lean bar:** [`docs/planning/LEAN_CNC_SCOPE.md`](docs/planning/LEAN_CNC_SCOPE.md)

Do **not** mark SPK-0623 `[x]` until the personal-use exit below is honestly met (agent UI driver OK; no rubber stamp).

## DoD reminder

Each feature needs **Engine + UI + Persist + Verify**. Build-only does not count. Numeric / G-code truth = CLTs + goldens, not vision.

## Track exits (code — done 2026-08-04)

| Track | Focus | Gate card | Status |
| --- | --- | --- | --- |
| 1 | Document spine | SPK-1100 | [x] |
| 2 | Design editor | SPK-1101 | [x] |
| 3 | Toolpaths + preview + sign | SPK-1102, 1103, 1106 | [x] |
| 4 | Machine handoff | SPK-1104 | [x] |
| 5 | XCTest / goldens / docs | SPK-1105 | [x] (429/429); SPK-0623 still `[ ]` until UI acceptance |
| 6 | Phases H–K | after SPK-0623 | blocked until personal gate |

## Personal-use SPK-0623 exit

Mark `[x]` only when **all** are true:

1. [x] Tracks 1–5 code + CLTs green  
2. [ ] **UI acceptance driver** completes G1 + G2 scripts in `UI_ACCEPTANCE_DRIVER.md` (agent+vision+computer-control allowed)  
3. [ ] Safety UI gates observed: dirty export block, V-Carve open-vector block, Hold/Reset visible when connected, **no auto-run on G-code load**  
4. [ ] Open P0 UI bugs from the driver filed as SPK cards (or fixed) — zero unexplained blockers  

**Not required (deferred `[-]`):**

- [-] SPK-0614 license  
- [-] SPK-0615 Apple Developer credentials  
- [-] SPK-0621 notarization  
- [-] SPK-0622 public GitHub Release / DMG  
- [-] SPK-1009 App Store  
- [!] SPK-0419 live air-cut — optional when hardware available; **not** a personal-0623 blocker  

**0.1 mm metrology:** trust `ShopPilotVerify*` / goldens; vision only confirms UI chrome and “preview not blank / path looks present.”

## Sign-off (personal)

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Owner | — | — | Pending UI acceptance driver report |
| Agent (driver) | — | — | Attach PASS/FAIL table + bug cards; do not self-flip 0623 without owner OK |
