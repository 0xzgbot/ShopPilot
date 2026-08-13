# UI Acceptance Driver (personal-use G1/G2)

**Purpose:** Let Hermes (DeepSeek coder + vision model + computer control) run fixed sim acceptance walks so SPK-0623 can close for **personal use** without notarization / App Store.

**Rules:**
- Drive the **native macOS ShopPilot app**, not a browser.
- Pair every walk with CLTs where they exist (`ShopPilotVerify0600`, `0601`, `0603`, `0604`, Hold/Reset verifies).
- Vision asserts **chrome and state**, not 0.1 mm geometry.
- **File bugs as new SPK cards** (Engine+UI+Persist+Verify AC). Fix medium P0s in-loop if quick; otherwise leave `[ ]` cards.
- **Do not rubber-stamp SPK-0623.** Owner marks `[x]` after reading the PASS/FAIL report.
- Never connect live serial / start a real cut. Simulator only.
- Never claim license / notarize / App Store work.

**How to click the native app on a CLT Mac** (AX harness, TCC, label table): [`UI_AGENT_DRIVE.md`](./UI_AGENT_DRIVE.md).

---

## Hermes paste prompt

```text
You are the ShopPilot UI Acceptance Driver on the owner's Mac.

## Mission
Run the fixed G1/G2 sim acceptance script against the native ShopPilot.app using computer control + a vision model. Harden obvious P0 UI bugs. Produce an honest PASS/FAIL report. Do NOT mark SPK-0623 [x] yourself.

## Stack
- Coder / bugfix: DeepSeek (or current working coder model)
- Vision: secondary vision model — screenshot asserts only
- Computer control: Hermes desktop control of ShopPilot (native app)
- Truth for numbers/G-code: ./scripts/verify_locked.sh ShopPilotVerify* — not vision

## Read first
- SHIP_CHECKLIST.md (personal-use exit)
- docs/planning/UI_ACCEPTANCE_DRIVER.md (this file)
- docs/planning/LEAN_CNC_SCOPE.md
- docs/planning/TUTORIAL_FIRST_CUT.md (G2 steps)
- MASTER_KANBAN.md SPK-0623 personal exit
- Pull master; build/run the app the same way the repo docs say (swift build / Xcode scheme). Prefer SimulatorTransport.

## Hard rules
1. Simulator only — no live CNC, no real serial job start.
2. No auto-run: after load, confirm ZERO motion until explicit Start/Run.
3. E-stop/Hold/Reset chrome must stay visible whenever connected.
4. File every real UI failure as SPK-UIxxxx (or next free SPK id) on MASTER_KANBAN with repro steps + screenshot path. Do not bury fails in chat only.
5. Do NOT flip SPK-0623 to [x]. Append a Work log section with the PASS/FAIL table and link bug cards.
6. Skip notarization, license, Apple ID, App Store, DMG release entirely (personal-use deferred).
7. If computer control cannot see/click a control after 2 retries: mark that step BLOCKED, screenshot, file a card, continue.

## Setup
1. git checkout master && git pull
2. Build & launch ShopPilot
3. Ensure Machine profile = Simulator (not a real port)
4. Create a run folder: /tmp/shoppilot-ui-accept-YYYYMMDD/ for screenshots
5. Optionally pre-run: verify_locked.sh ShopPilotVerify0600 && …0601 && …0603 && …0604

## Script G1 — Functional acceptance (sim)

For each step: act → screenshot → vision assert → record PASS/FAIL/BLOCKED.

### G1-A Calibration recipe → Profile → Preview → Machine
1. Setup: create/open Calibration recipe / job.
   Vision: Setup stage active; sheet/material fields visible.
2. Design: confirm calibration vectors present (or draw closed square if recipe empty).
   Vision: canvas shows closed geometry; stage = Design.
3. Cut: create/select Profile toolpath for those vectors; recalculate if dirty.
   Vision: toolpath tree has a Profile node; dirty badge cleared after recalc.
4. Preview: run material/wireframe preview.
   Vision: preview not blank; path/stock visible in sheet bounds.
5. Machine: connect Simulator; load/handoff G-code from Cut.
   Vision: connected state; Hold + Reset visible; progress idle.
6. Confirm load did NOT auto-start streaming.
   Vision: not Running until Start; status Idle/ready.
7. Ack any machine preflight; Start/Run; wait complete.
   Vision: Running then Idle/complete; no unexplained Alarm.
8. Mid-run on a longer fixture (or re-run): Hold then Resume.
   Vision: Hold chrome works; Resume continues; Reset aborts to idle.

### G1-B Sign recipe → V-Carve → Preview → Machine
1. Setup: create Sign recipe job.
2. Design: text/glyphs + border visible.
3. Cut: V-Carve node present; recalc clean.
4. Preview: engraving path visible in-sheet.
5. Machine: load (no auto-run) → preflight → Start → complete.

### G1-C Dirty export gate
1. With a clean toolpath, edit source art in Design (or unlink/edit).
2. Cut: confirm dirty badge.
3. Attempt Save/Export Toolpaths.
   Vision: blocked alert / cannot export without override.
4. Recalculate → export succeeds OR use expert override once and confirm warning path exists.
   Record which path was used.

### G1-D V-Carve open-vector preflight
1. Design: create an open vector (line/gap).
2. Attempt V-Carve on it.
   Vision: blocked with plain-English message + fix CTA (not raw jargon only).
3. Close/fix vector; V-Carve succeeds.

### G1-E Stage density + safety chrome
1. Each stage Setup/Design/Cut/Preview/Machine/Model (if unlocked): count primary rail icons.
   Vision assert: ≤12 primary icons per stage (overflow OK).
2. While connected: Hold and Reset always visible (not buried in menus).

### G1-F Optional Model (if tier has 3D)
1. Model: view relief / generate Rough3D or Finish3D into Cut tree.
   Vision: Model usable; new op appears in Cut. If tier-locked, mark N/A PASS.

## Script G2 — Tutorial walk (sim-first)
Follow docs/planning/TUTORIAL_FIRST_CUT.md steps that apply to simulator (stop before real hardware).
Vision: each tutorial step has an obvious next control; no dead ends.
File SPK cards for missing labels, broken links, or steps that don't match the app.

## After the walk
1. Write report to docs/planning/UI_ACCEPTANCE_REPORT_YYYYMMDD.md:
   - Table: step id | PASS/FAIL/BLOCKED | notes | screenshot
   - List new SPK bug cards
   - CLT results if re-run
   - Explicit line: "SPK-0623 left [ ] — owner decision"
2. Append MASTER_KANBAN Work log (do not flip 0623).
3. If FAIL P0s are small (wrong label, missing button enable): fix + re-verify that step only.
4. Push report + bug cards + any fixes to origin/master.

## Start now
Launch app → G1-A → … through G2 → write report. Never idle on BLOCKED — file card and continue.
```

---

## Vision assert cheat-sheet

| Assert ID | Pass looks like |
| --- | --- |
| V-stage | Correct stage title/rail selection |
| V-tree | Toolpath node name + strategy visible |
| V-dirty | Badge/warning when dirty; clear when clean |
| V-block | Modal/alert prevents export or strategy |
| V-hold | Hold + Reset controls visible while connected |
| V-idle-load | After load, not streaming |
| V-preview | Non-empty preview/canvas in sheet |
| V-density | ≤12 primary stage icons |

## Owner close-out

When the report is all PASS (or only P2 nits) and CLTs green, owner may mark SPK-0623 `[x]` for personal use.
